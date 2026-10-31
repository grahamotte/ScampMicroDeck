import AppKit

let config = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: "config.json"))) as! [String: Any]
let targets = (config["apps"] as! [String: Any])["targets"] as! [String: Any]
let macos = (targets["apple"] as! [String: Any])["macos"] as! [String: Any]
let bundleIdentifier = "\(macos["bundleIdentifier"] as! String).debug"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("app:debug: \(message)\n".utf8))
    exit(1)
}

if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
    fail("\(bundleIdentifier) is not running; launch the Debug build with mise simulate macos")
}

let id = UUID().uuidString
let center = DistributedNotificationCenter.default()
var reply: [String: String]?
let observer = center.addObserver(forName: Notification.Name("\(bundleIdentifier).debug.reply"), object: nil, queue: nil) { note in
    guard let object = (note.object as? String)?.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: object) as? [String: String],
          message["id"] == id else { return }
    reply = message
}

let request = try JSONSerialization.data(withJSONObject: ["id": id, "command": CommandLine.arguments[1]])
center.postNotificationName(Notification.Name("\(bundleIdentifier).debug"), object: String(decoding: request, as: UTF8.self), userInfo: nil, deliverImmediately: true)

let deadline = Date(timeIntervalSinceNow: 10)
while reply == nil, Date() < deadline {
    RunLoop.main.run(mode: .default, before: deadline)
}
center.removeObserver(observer)

guard let reply else { fail("no reply from \(bundleIdentifier) within 10 seconds; rebuild and relaunch the Debug build with mise simulate macos") }
if let error = reply["error"] { fail(error) }
