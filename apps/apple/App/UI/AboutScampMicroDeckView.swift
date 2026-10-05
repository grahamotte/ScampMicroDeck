import AppKit
import SwiftUI

struct AboutScampMicroDeckView: View {
    static let windowID = "about-scamp"

    private let sourceCodeURL = URL(string: "https://github.com/grahamotte/ScampMicroDeck")!

    private var appIcon: NSImage {
        NSApplication.shared.applicationIconImage
    }

    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Scamp Micro Deck"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? version
        return "Version \(version) (\(build))"
    }

    private var copyrightText: String? {
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        return copyright?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? copyright : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    Text(displayName)
                        .font(.title.bold())

                    Text("A native macOS music player for local folders of audio files, designed to mimic the tedious charm of a real vinyl record player.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy")
                        .font(.headline)

                    Text("Scamp Micro Deck does not collect any personal information or telemetry.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Bugs?")
                        .font(.headline)

                    Link("Open an issue!", destination: sourceCodeURL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .frame(width: 460)
    }
}

private struct AboutFeatureRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
    }
}

#Preview {
    AboutScampMicroDeckView()
}
