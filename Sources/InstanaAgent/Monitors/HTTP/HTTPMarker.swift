import Foundation

protocol HTTPMarkerDelegate: AnyObject {
    func httpMarkerDidFinish(_ marker: HTTPMarker)
}

/// Remote call markers are used to track remote calls.

@objc public class HTTPMarker: NSObject {
    enum State {
        case started, failed(error: Error), finished(responseCode: Int), canceled
    }

    enum Trigger {
        case manual, automatic
    }

    let url: URL
    let method: String
    let trigger: Trigger
    let startTime: Instana.Types.Milliseconds
    let viewName: String?
    private(set) var backendTracingID: String?
    private(set) var responseSize: Instana.Types.HTTPSize?
    private var endTime: Instana.Types.Milliseconds?
    private(set) var state: State = .started
    private weak var delegate: HTTPMarkerDelegate?

    init(url: URL, method: String, trigger: Trigger, delegate: HTTPMarkerDelegate?, viewName: String? = nil) {
        startTime = Date().millisecondsSince1970
        self.url = url
        self.method = method
        self.delegate = delegate
        self.trigger = trigger
        self.viewName = viewName
    }
}

extension HTTPMarker {
    /// Invoke this method when the reponse size has been determined.
    ///
    /// - Parameters:
    ///   - responseSize: Size of the response.
    ///
    /// Note: You must make sure to trigger `set(responseSize:` before calling the finish or cancel method
    @objc public func set(responseSize: Instana.Types.HTTPSize) {
        guard case .started = state else { return }
        self.responseSize = responseSize
    }

    /// Set the Backend Tracing ID
    ///
    /// - Parameters:
    ///   - backendTracingID: Backend Tracing ID.
    ///
    /// Set the Backend Tracing ID to map the response received by client with the sending server.
    /// The Backend Tracing ID will be sent by the server via the HTTP header field
    /// This ID will be set automatically if you choose automatic HTTP monitoring.
    ///
    /// Note: You must make sure to trigger `set(backendTracingID:` before calling the finish or canceled method
    @objc public func set(backendTracingID: String) {
        guard case .started = state else { return }
        self.backendTracingID = backendTracingID
    }

    /// Invoke this method after the request has successfuly finish.
    ///
    /// - Parameters:
    ///   - responseCode: Usually a HTTP status code.
    ///
    /// Note: Make sure you don't call any methods on this HTTPMarker after you called finish
    @objc public func finish(responseCode: Int) {
        guard case .started = state else { return }
        state = .finished(responseCode: responseCode)
        endTime = Date().millisecondsSince1970
        delegate?.httpMarkerDidFinish(self)
    }

    /// Invoke this method after the request has failed to finish.
    ///
    /// - Parameters:
    ///   - error: Error that explains what happened.
    ///
    /// Note: Make sure you don't call any methods on this HTTPMarker after you called finish
    @objc public func finish(error: Error) {
        guard case .started = state else { return }
        state = .failed(error: error)
        endTime = Date().millisecondsSince1970
        delegate?.httpMarkerDidFinish(self)
    }

    /// Invoke this method if the reuqest has been canceled before completion.
    /// Note: Make sure you don't call more methods on this HTTPMarker after you called canceled
    @objc public func cancel() {
        guard case .started = state else { return }
        state = .canceled
        endTime = Date().millisecondsSince1970
        delegate?.httpMarkerDidFinish(self)
    }

    ///
    /// Duration of the request. Available after one of the completion method has been invoked.
    var duration: Instana.Types.Milliseconds {
        guard let endTime = self.endTime else { return 0 }
        return Instana.Types.Milliseconds(endTime - startTime)
    }
}

extension HTTPMarker {
    func createBeacon() -> Beacon {
        var error: Error?
        var responseCode: Int?

        switch state {
        case .started:
            break
        case .canceled:
            error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
        case let .finished(code):
            responseCode = code
        case let .failed(theError):
            error = theError
        }

        return HTTPBeacon(timestamp: startTime,
                          duration: duration,
                          method: method,
                          url: url,
                          responseCode: responseCode ?? -1,
                          responseSize: responseSize,
                          error: error,
                          backendTracingID: backendTracingID,
                          viewName: viewName)
    }
}

extension HTTPMarker {
    @objc public class HTTPSize: NSObject {
        var headerBytes: Instana.Types.Bytes?
        var bodyBytes: Instana.Types.Bytes?
        var bodyBytesAfterDecoding: Instana.Types.Bytes?

        // Need multiple init because of ObjC interop
        @objc public override init() {
            super.init()
            headerBytes = nil
            bodyBytes = nil
            bodyBytesAfterDecoding = nil
        }

        @objc public init(header: Instana.Types.Bytes) {
            super.init()
            headerBytes = header
            bodyBytes = nil
            bodyBytesAfterDecoding = nil
        }

        @objc public init(header: Instana.Types.Bytes, body: Instana.Types.Bytes) {
            super.init()
            headerBytes = header
            bodyBytes = body
            bodyBytesAfterDecoding = nil
        }

        @objc public init(header: Instana.Types.Bytes, body: Instana.Types.Bytes, bodyAfterDecoding: Instana.Types.Bytes) {
            super.init()
            headerBytes = header
            bodyBytes = body
            bodyBytesAfterDecoding = bodyAfterDecoding
        }

        @objc public class func size(for response: URLResponse, transactionMetrics: [URLSessionTaskTransactionMetrics]) -> HTTPSize {
            guard #available(iOS 13.0, *) else { return size(response: response) }
            let size = HTTPSize()
            size.headerBytes = transactionMetrics.map { $0.countOfResponseHeaderBytesReceived }.reduce(0, +)
            size.bodyBytes = transactionMetrics.map { $0.countOfResponseBodyBytesReceived }.reduce(0, +)
            size.bodyBytesAfterDecoding = transactionMetrics.map { $0.countOfResponseBodyBytesAfterDecoding }.reduce(0, +)
            return size
        }

        @objc public class func size(response: URLResponse) -> HTTPSize {
            let size = HTTPSize()
            if let headerFields = (response as? HTTPURLResponse)?.allHeaderFields {
                size.headerBytes = Instana.Types.Bytes(NSKeyedArchiver.archivedData(withRootObject: headerFields).count)
            }
            size.bodyBytes = response.expectedContentLength
            return size
        }
    }
}