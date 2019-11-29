//  Created by Nikola Lajic on 12/25/18.
//  Copyright © 2018 Nikola Lajic. All rights reserved.

import Foundation

protocol HTTPMarkerDelegate: class {
    func finalized(marker: HTTPMarker)
}

/// Remote call markers are used to track remote calls.
///
/// For external use they are generated by `Instana.remoteCallInstrumentation.markCall(to:method:)`.
@objc public class HTTPMarker: NSObject {
    enum State {
        case started, failed(error: Error), finished(responseCode: Int), canceled
    }
    enum Trigger {
        case manual, automatic
    }
    let url: String
    let method: String
    let trigger: Trigger
    let requestSize: Instana.Types.Bytes
    let startTime: Instana.Types.Milliseconds
    let connectionType: InstanaNetworkMonitor.ConnectionType?
    private(set) var responseSize: Instana.Types.Bytes = 0
    private var endTime: Instana.Types.Milliseconds?
    private(set) var state: State = .started
    private weak var delegate: HTTPMarkerDelegate?
    
    init(url: String, method: String, trigger: Trigger = .automatic, requestSize: Instana.Types.Bytes = 0, connectionType: InstanaNetworkMonitor.ConnectionType? = nil, delegate: HTTPMarkerDelegate) {
        self.startTime = Date().millisecondsSince1970
        self.url = url
        self.method = method
        self.delegate = delegate
        self.trigger = trigger
        self.requestSize = requestSize
        self.connectionType = connectionType
    }
}

extension HTTPMarker {

//    TODO: what is the following for?? can be removed?
//    /// Adds tracking headers to a mutable url request.
//    ///
//    /// This should be used when manually instrumenting calls to a backend that has Instana tracing.
//    /// - Parameter request: Request that will be modified to include tracking headers.
//    @objc public func addTrackingHeaders(to request: NSMutableURLRequest?) {
//        guard let request = request else { return }
//        headers.forEach { (key, value) in request.addValue(value, forHTTPHeaderField: key) }
//    }
//
//    /// Adds tracking headers to a url request.
//    ///
//    /// This should be used when manually instrumenting calls to a backend that has Instana tracing.
//    /// - Parameter request: Request that will be modified to include tracking headers.
//    public func addTrackingHeaders(to request: inout URLRequest) {
//        headers.forEach { (key, value) in request.addValue(value, forHTTPHeaderField: key) }
//    }
//
//    /// If you are not using `URLRequest` or `NSMutableURLRequest` you can add these values to your request headers
//    /// when making calls to a backend that has Instana.
//    @objc public var headers: [String: String] {
//        get {
//            return ["X-INSTANA-T": eventId]
//        }
//    }
    
    /// Invoke this method after the request has successfuly finished.
    ///
    /// - Parameters:
    ///   - responseCode: Usually a HTTP status code.
    ///   - responseSize: Optional, size of the response.
    @objc public func endedWith(responseCode: Int, responseSize: Instana.Types.Bytes = 0) {
        guard case .started = state else { return }
        state = .finished(responseCode: responseCode)
        self.responseSize = responseSize
        endTime = Date().millisecondsSince1970
        delegate?.finalized(marker: self)
    }
    
    /// Invoke this method after the request has failed to finish.
    ///
    /// - Parameters:
    ///   - error: Error that explains what happened.
    ///   - responseSize: Optional, size of the response.
    @objc public func endedWith(error: Error, responseSize: Instana.Types.Bytes = 0) {
        guard case .started = state else { return }
        state = .failed(error: error)
        self.responseSize = responseSize
        endTime = Date().millisecondsSince1970
        delegate?.finalized(marker: self)
    }
    
    /// Invoke this method if the reuqest has been canceled before completion.
    @objc public func canceled() {
        guard case .started = state else { return }
        state = .canceled
        endTime = Date().millisecondsSince1970
        delegate?.finalized(marker: self)
    }
    
    /// Public because of Obj-C compatibility.
    ///
    /// Duration of the request. Available after one of the completion method has been invoked.
    @objc public func duration() -> Instana.Types.Milliseconds {
        guard let endTime = self.endTime else { return 0 }
        return Instana.Types.Milliseconds(endTime - startTime)
    }
}

extension HTTPMarker {
    func createEvent() -> Event {
        let result: String
        var responseCode: Int? = nil
        
        switch state {
        case .started:
            result = "started"
        case .canceled:
            result = "canceled"
        case .finished(let rc):
            result = "finished"
            responseCode = rc
        case .failed(let error):
            result = String(describing: error)
        }

        return HTTPEvent(timestamp: startTime,
                         duration: duration(),
                         method: method,
                         url: url,
                         connectionType: connectionType,
                         responseCode: responseCode ?? -1,
                         requestSize: requestSize,
                         responseSize: responseSize,
                         result: result)
    }
}
