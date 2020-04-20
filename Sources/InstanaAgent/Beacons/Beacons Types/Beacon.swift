import Foundation

/// Base class for Beacon.
class Beacon: Identifiable {
    let id = UUID()
    let sessionID: UUID
    var timestamp: Instana.Types.Milliseconds = Date().millisecondsSince1970
    let viewName: String?

    init(timestamp: Instana.Types.Milliseconds = Date().millisecondsSince1970,
         sessionID: UUID = Instana.current?.session.id ?? UUID(),
         viewName: String? = nil) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.viewName = viewName
    }
}

enum BeaconResult: Equatable {
    static func == (lhs: BeaconResult, rhs: BeaconResult) -> Bool {
        return lhs.error as NSError? == rhs.error as NSError?
    }

    case success
    case failure(Error)

    var error: Error? {
        switch self {
        case .success: return nil
        case let .failure(error): return error
        }
    }
}

