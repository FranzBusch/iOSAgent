
import Foundation
import Gzip

/// Reporter to queue and submit the Beacons
public class Reporter {
    
    typealias Submitter = (Beacon) -> Void
    typealias NetworkLoader = (URLRequest, @escaping (InstanaNetworking.Result) -> Void) -> Void
    var completion: (BeaconResult) -> Void = {_ in}
    private var backgroundQueue = DispatchQueue(label: "com.instana.ios.app.background", qos: .background, attributes: .concurrent)
    private var timer: Timer?
    private let send: NetworkLoader
    private let batterySafeForNetworking: () -> Bool
    private let networkUtility: NetworkUtility
    private var suspendReporting: Set<InstanaConfiguration.SuspendReporting> { configuration.suspendReporting }
    private (set) var queue = InstanaPersistableQueue<CoreBeacon>()
    private let configuration: InstanaConfiguration

    // MARK: Init
    init(_ configuration: InstanaConfiguration,
         useGzip: Bool = true,
         batterySafeForNetworking: @escaping () -> Bool = { InstanaSystemUtils.battery.safeForNetworking },
         networkUtility: NetworkUtility = NetworkUtility(),
         send: @escaping NetworkLoader = InstanaNetworking().send(request:completion:)) {
        self.networkUtility = networkUtility
        self.configuration = configuration
        self.batterySafeForNetworking = batterySafeForNetworking
        self.send = send

        networkUtility.connectionUpdateHandler = {[weak self] connectionType in
            guard let self = self else { return }
            if connectionType != .none {
                self.flushQueue()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func submit(_ beacon: Beacon) {
        guard let coreBeacon = try? CoreBeaconFactory(configuration).map(beacon) else { return }
        queue.add(coreBeacon)
        scheduleFlush()
    }

    func scheduleFlush() {
        timer?.invalidate()
        let interval = batterySafeForNetworking() ? configuration.transmissionDelay : configuration.transmissionLowBatteryDelay
        if interval == 0.0 {
            flushQueue()
            return // No timer needed - flush directly
        }
        let t = InstanaTimerProxy.timer(proxied: self, timeInterval: interval, userInfo: CFAbsoluteTimeGetCurrent(), repeats: false)
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }
}

extension Reporter: InstanaTimerProxiedTarget {
    func onTimer(timer: Timer) {
        flushQueue()
    }
}

extension Reporter {
    func flushQueue() {
        backgroundQueue.async {
            self._flushQueue()
        }
    }

    private func _flushQueue() {
        let connectionType = networkUtility.connectionType
        guard connectionType != .none else {
            complete([], .failure(InstanaError(code: .offline, description: "No connection available")))
            return
        }
        if suspendReporting.contains(.cellularConnection) && connectionType == .cellular {
            complete([], .failure(InstanaError(code: .noWifiAvailable, description: "No WIFI Available")))
            return
        }
        if suspendReporting.contains(.lowBattery) && !batterySafeForNetworking() {
            complete([], .failure(InstanaError(code: .lowBattery, description: "Battery too low for flushing")))
            return
        }

        let beacons = queue.items
        let request: URLRequest
        do {
            request = try createBatchRequest(from: beacons)
        } catch {
            complete([], .failure(error))
            return
        }
        send(request) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.complete(beacons, .failure(error))
            case .success(200...299):
                self.complete(beacons, .success)
            case .success(let statusCode):
                self.complete(beacons, .failure(InstanaError(code: .invalidResponse, description: "Invalid repsonse status code: \(statusCode)")))
            }
        }
    }
    
    func complete(_ beacons: [CoreBeacon],_ result: BeaconResult) {
        switch result {
        case .success:
            Instana.current.logger.add("Did send beacons \(beacons)")
            queue.remove(beacons)
        case .failure(let error):
            Instana.current.logger.add("Failed to send Beacon batch: \(error)", level: .warning)
        }
        completion(result)
    }
}

extension Reporter {

    func createBatchRequest(from beacons: [CoreBeacon]) throws -> URLRequest {
        guard !configuration.key.isEmpty else {
            throw InstanaError(code: .notAuthenticated, description: "Missing application key. No data will be sent.")
        }

        var urlRequest = URLRequest(url: configuration.reportingURL)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("text/plain", forHTTPHeaderField: "Content-Type")

        let data = beacons.asString.data(using: .utf8)

        if configuration.gzipReport, let gzippedData = try? data?.gzipped(level: .bestCompression) {
            urlRequest.httpBody = gzippedData
            urlRequest.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            urlRequest.setValue("\(gzippedData.count)", forHTTPHeaderField: "Content-Length")
        } else {
            urlRequest.httpBody = data
            urlRequest.setValue("\(data?.count ?? 0)", forHTTPHeaderField: "Content-Length")
        }

        return urlRequest
    }
}
