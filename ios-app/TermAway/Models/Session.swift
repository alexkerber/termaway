import Foundation

struct Session: Identifiable, Codable {
    var id: String { name }
    let name: String
    let clientCount: Int
    let createdAt: Date?

    init(name: String, clientCount: Int = 0, createdAt: Date? = nil) {
        self.name = name
        self.clientCount = clientCount
        self.createdAt = createdAt
    }
}

// Server message types
enum ServerMessage {
    case sessions([Session])
    case output(String)
    case created(String)
    case attached(String)
    case killed(String)
    case renamed(String, String)
    case exited(String, Int)
    case error(String)
    case unknown

    init(from json: [String: Any]) {
        guard let type = json["type"] as? String else {
            self = .unknown
            return
        }

        switch type {
        case "sessions":
            if let list = json["list"] as? [[String: Any]] {
                let sessions = list.compactMap { item -> Session? in
                    guard let name = item["name"] as? String else { return nil }
                    let clientCount = item["clientCount"] as? Int ?? 0
                    return Session(name: name, clientCount: clientCount)
                }
                self = .sessions(sessions)
            } else {
                self = .sessions([])
            }

        case "output":
            if let data = json["data"] as? String {
                self = .output(data)
            } else {
                self = .unknown
            }

        case "created":
            if let name = json["name"] as? String {
                self = .created(name)
            } else {
                self = .unknown
            }

        case "attached":
            if let name = json["name"] as? String {
                self = .attached(name)
            } else {
                self = .unknown
            }

        case "killed":
            if let name = json["name"] as? String {
                self = .killed(name)
            } else {
                self = .unknown
            }

        case "renamed":
            if let oldName = json["oldName"] as? String,
               let newName = json["newName"] as? String {
                self = .renamed(oldName, newName)
            } else {
                self = .unknown
            }

        case "exited":
            if let name = json["name"] as? String,
               let exitCode = json["exitCode"] as? Int {
                self = .exited(name, exitCode)
            } else {
                self = .unknown
            }

        case "error":
            if let message = json["message"] as? String {
                self = .error(message)
            } else {
                self = .unknown
            }

        default:
            self = .unknown
        }
    }
}
