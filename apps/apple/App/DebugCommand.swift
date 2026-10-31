#if APP_DEV
import Foundation

struct DebugRequest: Codable, Equatable {
    let id: String
    let command: String
}

struct DebugReply: Codable, Equatable {
    let id: String
    let error: String?
}

enum DebugCommand: Equatable {
    enum Modifier: Character {
        case command = "c"
        case shift = "s"
        case option = "o"
        case control = "t"
        case function = "f"
        case numericPad = "n"
    }

    static let arrows: [UInt16: Int] = [123: 0xF702, 124: 0xF703, 125: 0xF701, 126: 0xF700]

    case snap(path: String, window: String?)
    case frame(width: Double, height: Double)
    case action(String)
    case key(code: UInt16, modifiers: Set<Modifier>, characters: String)
    case type(String)
    case custom(String, [String])

    init?(_ command: String) {
        let parts = command.components(separatedBy: "|")
        let arguments = Array(parts.dropFirst())
        switch parts[0] {
        case "":
            return nil
        case "snap":
            guard let path = arguments.first, !path.isEmpty else { return nil }
            self = .snap(path: path, window: arguments.count > 1 ? arguments[1] : nil)
        case "frame":
            guard arguments.count == 2, let width = Double(arguments[0]), let height = Double(arguments[1]) else { return nil }
            self = .frame(width: width, height: height)
        case "action":
            guard let selector = arguments.first, !selector.isEmpty else { return nil }
            self = .action(selector)
        case "key":
            guard let code = arguments.first.flatMap(UInt16.init) else { return nil }
            var modifiers = Set((arguments.count > 1 ? arguments[1] : "").compactMap(Modifier.init))
            var characters = arguments.count > 2 ? arguments[2] : ""
            if let arrow = Self.arrows[code], let scalar = UnicodeScalar(arrow) {
                modifiers.formUnion([.function, .numericPad])
                characters = String(Character(scalar))
            }
            self = .key(code: code, modifiers: modifiers, characters: characters)
        case "type":
            guard arguments.count == 1 else { return nil }
            self = .type(arguments[0])
        default:
            self = .custom(parts[0], arguments)
        }
    }
}
#endif
