#if APP_DEV && os(macOS)
import AppKit

enum DebugHooks {
    struct Failure: LocalizedError {
        let errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    static func install(custom: @escaping @MainActor (String, [String]) throws -> Void = { name, _ in throw Failure("unknown command \(name)") }) {
        let name = Notification.Name("\(Bundle.main.bundleIdentifier ?? "app").debug")
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            guard let object = (note.object as? String)?.data(using: .utf8),
                  let request = try? JSONDecoder().decode(DebugRequest.self, from: object) else { return }
            MainActor.assumeIsolated {
                var error: String?
                do {
                    try run(request.command, custom: custom)
                } catch let failure {
                    error = failure.localizedDescription
                }
                reply(DebugReply(id: request.id, error: error), to: name)
            }
        }
    }

    static func run(_ command: String, custom: (String, [String]) throws -> Void) throws {
        guard let command = DebugCommand(command) else { throw Failure("invalid command \(command)") }
        switch command {
        case .snap(let path, let title):
            guard let view = try window(titled: title).contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure("cannot capture window") }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure("cannot encode PNG") }
            try png.write(to: URL(filePath: path))
        case .frame(let width, let height):
            let window = try window(titled: nil)
            let frame = window.frame
            window.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height), display: true)
        case .action(let name):
            if !NSApp.sendAction(Selector(name), to: nil, from: nil),
               try window(titled: nil).firstResponder?.tryToPerform(Selector(name), with: nil) != true {
                throw Failure("no responder handled \(name)")
            }
        case .key(let code, let modifiers, let characters):
            let window = try window(titled: nil)
            let flags = modifiers.reduce(into: NSEvent.ModifierFlags()) { $0.insert(flag(for: $1)) }
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw Failure("cannot create key event") }
                if type == .keyDown, NSApp.mainMenu?.performKeyEquivalent(with: event) == true || window.performKeyEquivalent(with: event) { continue }
                window.sendEvent(event)
            }
        case .type(let text):
            guard let client = try window(titled: nil).firstResponder as? NSTextInputClient else { throw Failure("first responder does not accept text") }
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        case .custom(let name, let arguments):
            try custom(name, arguments)
        }
    }

    private static func reply(_ reply: DebugReply, to name: Notification.Name) {
        guard let data = try? JSONEncoder().encode(reply) else { return }
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("\(name.rawValue).reply"), object: String(decoding: data, as: UTF8.self), userInfo: nil, deliverImmediately: true)
    }

    private static func window(titled title: String?) throws -> NSWindow {
        if let title {
            guard let window = NSApp.windows.first(where: { $0.title == title }) else { throw Failure("no window titled \(title)") }
            return window
        }
        guard let window = NSApp.mainWindow ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.canBecomeMain }) else { throw Failure("no main window") }
        return window
    }

    private static func flag(for modifier: DebugCommand.Modifier) -> NSEvent.ModifierFlags {
        switch modifier {
        case .command: .command
        case .shift: .shift
        case .option: .option
        case .control: .control
        case .function: .function
        case .numericPad: .numericPad
        }
    }
}
#endif
