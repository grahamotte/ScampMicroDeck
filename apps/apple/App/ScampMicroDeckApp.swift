import SwiftUI

@main
struct ScampMicroDeckApp: App {
    @State private var playback = PlaybackController()
    @StateObject private var albumLibrary = AlbumLibraryController()
    @AppStorage("selectedTableTheme") private var selectedTableThemeRawValue = TableTheme.walnut.rawValue
    @AppStorage("selectedRecordTheme") private var selectedRecordThemeRawValue = RecordTheme.black.rawValue
    @AppStorage("selectedControlsTheme") private var selectedControlsThemeRawValue = ControlsTheme.silver.rawValue
    @AppStorage("hasSeenHowToUse") private var hasSeenHowToUse = false
    @State private var showsHowToUse = false
    @State private var showsLibrary = false

    init() {
        #if APP_DEV
        DebugHooks.install()
        #endif
    }

    private var selectedTableTheme: Binding<TableTheme> {
        Binding(
            get: { TableTheme(rawValue: selectedTableThemeRawValue) ?? .walnut },
            set: { selectedTableThemeRawValue = $0.rawValue }
        )
    }

    private var selectedRecordTheme: Binding<RecordTheme> {
        Binding(
            get: { RecordTheme(rawValue: selectedRecordThemeRawValue) ?? .black },
            set: { selectedRecordThemeRawValue = $0.rawValue }
        )
    }

    private var selectedControlsTheme: Binding<ControlsTheme> {
        Binding(
            get: { ControlsTheme(rawValue: selectedControlsThemeRawValue) ?? .silver },
            set: { selectedControlsThemeRawValue = $0.rawValue }
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                playback: playback,
                library: albumLibrary,
                tableTheme: selectedTableTheme,
                recordTheme: selectedRecordTheme,
                controlsTheme: selectedControlsTheme,
                showsLibrary: $showsLibrary,
                showsHowToUse: $showsHowToUse,
                dismissHowToUse: {
                    hasSeenHowToUse = true
                    showsHowToUse = false
                }
            )
            .task {
                guard !hasSeenHowToUse else { return }
                showsHowToUse = true
            }
        }
        .defaultSize(width: ScampMicroDeckLayout.windowWidth, height: ScampMicroDeckLayout.windowHeight)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            ScampMicroDeckCommands(
                playback: playback,
                tableTheme: selectedTableTheme,
                recordTheme: selectedRecordTheme,
                controlsTheme: selectedControlsTheme,
                showsHowToUse: $showsHowToUse
            )
            LibraryCommands(
                library: albumLibrary,
                playback: playback,
                showsLibrary: $showsLibrary
            )
        }

        Window("About Scamp Micro Deck", id: AboutScampMicroDeckView.windowID) {
            AboutScampMicroDeckView()
        }
        .defaultSize(width: 460, height: 520)
        .windowResizability(.contentSize)
    }
}

private struct ScampMicroDeckCommands: Commands {
    let playback: PlaybackController
    @Binding var tableTheme: TableTheme
    @Binding var recordTheme: RecordTheme
    @Binding var controlsTheme: ControlsTheme
    @Binding var showsHowToUse: Bool
    @Environment(\.openWindow) private var openWindow

    init(
        playback: PlaybackController,
        tableTheme: Binding<TableTheme>,
        recordTheme: Binding<RecordTheme>,
        controlsTheme: Binding<ControlsTheme>,
        showsHowToUse: Binding<Bool>
    ) {
        self.playback = playback
        _tableTheme = tableTheme
        _recordTheme = recordTheme
        _controlsTheme = controlsTheme
        _showsHowToUse = showsHowToUse
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Scamp Micro Deck") {
                openWindow(id: AboutScampMicroDeckView.windowID)
            }
        }

        CommandMenu("Theme") {
            Button("Randomize Themes") {
                if let tableTheme = TableTheme.allCases.randomElement() {
                    self.tableTheme = tableTheme
                }
                if let recordTheme = RecordTheme.allCases.randomElement() {
                    self.recordTheme = recordTheme
                }
                if let controlsTheme = ControlsTheme.allCases.randomElement() {
                    self.controlsTheme = controlsTheme
                }
            }

            Divider()

            Picker("Table Theme", selection: $tableTheme) {
                ForEach(TableTheme.allCases) { theme in
                    Text(theme.displayName)
                        .tag(theme)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Record Theme", selection: $recordTheme) {
                ForEach(RecordTheme.allCases) { theme in
                    Text(theme.displayName)
                        .tag(theme)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("Controls Theme", selection: $controlsTheme) {
                ForEach(ControlsTheme.allCases) { theme in
                    Text(theme.displayName)
                        .tag(theme)
                }
            }
            .pickerStyle(.inline)
        }

        CommandGroup(replacing: .help) {
            Button("Load Demo Album") {
                playback.loadDemoAlbum()
            }

            Button("Scamp Micro Deck Help") {
                showsHowToUse = true
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}
