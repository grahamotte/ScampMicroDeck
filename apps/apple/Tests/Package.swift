// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScampMicroDeck",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "ScampMicroDeckCore",
            path: "App",
            exclude: [
                "AppLayout.swift",
                "Assets.xcassets",
                "Config",
                "ContentView.swift",
                "DebugHooks.swift",
                "LibraryCommands.swift",
                "Resources",
                "ScampMicroDeckApp.swift",
                "Shaders",
                "UI",
            ],
            sources: [
                "DebugCommand.swift",
                "Playback/AudioPlayerEngine.swift",
                "Playback/AlbumLibrary.swift",
                "Playback/PlaybackController.swift",
                "Playback/PlaybackMediaRemoteBridge.swift",
                "Playback/PlaybackTrack.swift",
                "Playback/PlaylistLoader.swift",
                "Rendering/BlackRecordPressing.swift",
            ],
            swiftSettings: [.define("APP_DEV"), .swiftLanguageMode(.v5)],
        ),
        .testTarget(
            name: "ScampMicroDeckCoreTests",
            dependencies: ["ScampMicroDeckCore"],
            path: "Tests",
            exclude: ["Package.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)],
        ),
    ]
)
