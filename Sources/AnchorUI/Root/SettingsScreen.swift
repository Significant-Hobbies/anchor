import AnchorCore
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Small on purpose: what the app is doing with your data, and how to point an
/// AI at it. No preferences that change the product's mind for you.
public struct SettingsScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Query private var goals: [Goal]
    @State private var didCopy = false

    public init() {}

    private var mcpCommand: String {
        "claude mcp add anchor -- \(mcpBinaryPath)"
    }

    /// Ships inside the app bundle, so the path is stable per install.
    private var mcpBinaryPath: String {
        Bundle.main.url(forAuxiliaryExecutable: "anchor-mcp")?.path
            ?? Bundle.main.bundleURL.appending(path: "Contents/MacOS/anchor-mcp").path
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("On-device intelligence")
                        let availability = TaggingService.availability
                        HStack(spacing: Space.xs) {
                            Image(systemName: availability.isAvailable ? "sparkles" : "exclamationmark.triangle")
                                .foregroundStyle(availability.isAvailable ? theme.accent : theme.caution)
                            Text(availability.explanation)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Distraction notes never leave this device. Grouping and tagging run against Apple's on-device model, and fall back to built-in rules when it isn't available.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Storage", subtitle: "SwiftData, synced with iCloud")
                        labelled("Goals", "\(goals.count)")
                        labelled("Database", AnchorStore.storeURL().path)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Talk to your data", subtitle: "Anchor ships an MCP server")
                        Text("Register it once and Claude can answer questions like “what broke my focus most this month?” directly against your history — locally, read-only.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(mcpCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                            .padding(Space.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))

                        Button {
                            copy(mcpCommand)
                        } label: {
                            Label(didCopy ? "Copied" : "Copy command", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(QuietButtonStyle(expands: false))
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
            Spacer(minLength: Space.sm)
            Text(value)
                .font(.system(size: 12, design: value.contains("/") ? .monospaced : .default))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
