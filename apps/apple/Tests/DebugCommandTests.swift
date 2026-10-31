import XCTest
@testable import ScampMicroDeckCore

final class DebugCommandTests: XCTestCase {
    func testSnap() {
        XCTAssertEqual(DebugCommand("snap|/tmp/app.png"), .snap(path: "/tmp/app.png", window: nil))
        XCTAssertEqual(DebugCommand("snap|/tmp/app.png|Settings"), .snap(path: "/tmp/app.png", window: "Settings"))
        XCTAssertNil(DebugCommand("snap"))
        XCTAssertNil(DebugCommand("snap|"))
    }

    func testFrame() {
        XCTAssertEqual(DebugCommand("frame|1100|700"), .frame(width: 1100, height: 700))
        XCTAssertNil(DebugCommand("frame|1100"))
        XCTAssertNil(DebugCommand("frame|wide|700"))
    }

    func testAction() {
        XCTAssertEqual(DebugCommand("action|newDocument:"), .action("newDocument:"))
        XCTAssertNil(DebugCommand("action"))
    }

    func testKey() {
        XCTAssertEqual(DebugCommand("key|0|cs|a"), .key(code: 0, modifiers: [.command, .shift], characters: "a"))
        XCTAssertEqual(DebugCommand("key|36"), .key(code: 36, modifiers: [], characters: ""))
        XCTAssertEqual(DebugCommand("key|49|otx| "), .key(code: 49, modifiers: [.option, .control], characters: " "))
        XCTAssertNil(DebugCommand("key|return"))
        XCTAssertNil(DebugCommand("key"))
    }

    func testArrowKeys() {
        XCTAssertEqual(DebugCommand("key|126"), .key(code: 126, modifiers: [.function, .numericPad], characters: "\u{F700}"))
        XCTAssertEqual(DebugCommand("key|123|s|x"), .key(code: 123, modifiers: [.shift, .function, .numericPad], characters: "\u{F702}"))
    }

    func testType() {
        XCTAssertEqual(DebugCommand("type|Hello world"), .type("Hello world"))
        XCTAssertEqual(DebugCommand("type|"), .type(""))
        XCTAssertNil(DebugCommand("type"))
    }

    func testCustom() {
        XCTAssertEqual(DebugCommand("go|/tmp|now"), .custom("go", ["/tmp", "now"]))
        XCTAssertEqual(DebugCommand("undo"), .custom("undo", []))
        XCTAssertNil(DebugCommand(""))
    }

    func testRequest() throws {
        let request = DebugRequest(id: "1", command: "snap|/tmp/app.png")
        XCTAssertEqual(try JSONDecoder().decode(DebugRequest.self, from: JSONEncoder().encode(request)), request)
        XCTAssertThrowsError(try JSONDecoder().decode(DebugRequest.self, from: Data("snap|/tmp/app.png".utf8)))
    }

    func testReply() throws {
        XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(DebugReply(id: "1", error: nil))) as? [String: String], ["id": "1"])
        XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(DebugReply(id: "1", error: "no main window"))) as? [String: String], ["id": "1", "error": "no main window"])
    }
}
