// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AuthenticationServices
import AnchorCore
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Small on purpose: what the app is doing with your data, and how to point an
/// AI at it. No preferences that change the product's mind for you.
public struct SettingsScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.anchorPlatformSync) private var platform
    @Query private var goals: [Goal]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    #if os(macOS)
    @State private var didCopy = false
    #endif
    private let storeKind: AnchorStore.StoreKind

    public init(storeKind: AnchorStore.StoreKind = .persistent) {
        self.storeKind = storeKind
    }

    #if os(macOS)
    private var mcpCommand: String {
        "codex mcp add anchor -- \(mcpBinaryPath)"
    }

    /// Ships inside the app bundle, so the path is stable per install.
    private var mcpBinaryPath: String {
        Bundle.main.url(forAuxiliaryExecutable: "anchor-mcp")?.path
            ?? Bundle.main.bundleURL.appending(path: "Contents/MacOS/anchor-mcp").path
    }
    #endif

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
                        SectionHeader(
                            "Project rates",
                            subtitle: "New sessions preserve the rate that was active when they started"
                        )
                        if projects.isEmpty {
                            Text("Create a project from the timer, then set its hourly rate here.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                        } else {
                            ForEach(projects) { project in
                                ProjectBillingRow(project: project) {
                                    project.hourlyRate = max(0, project.hourlyRate)
                                    project.currencyCode = project.currencyCode
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .uppercased()
                                    if project.currencyCode.isEmpty { project.currencyCode = "USD" }
                                    try? context.save()
                                }
                            }
                        }
                    }
                }

                #if os(macOS)
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Computer activity", subtitle: "Reminds you after 5 active minutes without a running timer")
                        Text("Anchor stores only aggregate active, tracked, and away seconds. It never records app names, windows, websites, keys, or pointer locations.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                #endif

                if let platform, let account = platform.account {
                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(
                                "Significant Hobbies Hub",
                                subtitle: "Optional visibility for finished session summaries"
                            )
                            Text("iCloud keeps your full Anchor data available across your Mac, iPhone, and Apple Watch.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("The Hub receives only the goal, start and end times, focused duration, outcome, and interruption count. Distraction notes never leave your Apple devices.")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)

                            labelled("Hub status", hubStatus(platform: platform, signedIn: account.isSignedIn))
                            labelled("Waiting locally", "\(platform.pendingCount)")
                            labelled("Last successful Hub sync", lastSyncText(platform.receipt.lastSuccessfulAt))

                            if account.isSignedIn {
                                Label(
                                    account.session?.email ?? "Personal account",
                                    systemImage: "person.crop.circle.badge.checkmark"
                                )
                                .font(.system(size: 12, weight: .medium))
                                if let failure = platform.receipt.failure {
                                    Text(failure.explanation(pendingCount: platform.pendingCount))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(theme.caution)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Button(platform.isSyncing ? "Syncing…" : "Sync now") {
                                    Task { await platform.synchronize(announcing: true) }
                                }
                                .buttonStyle(QuietButtonStyle(expands: false))
                                .disabled(platform.isSyncing)
                                Button("Sign out") { Task { await platform.disconnect() } }
                                    .buttonStyle(QuietButtonStyle(expands: false))
                            } else {
                                SignInWithAppleButton(.continue) { request in
                                    account.prepareApple(request)
                                } onCompletion: { result in
                                    Task {
                                        await account.completeApple(result)
                                        if account.isSignedIn {
                                            await platform.synchronize(announcing: true)
                                        }
                                    }
                                }
                                .signInWithAppleButtonStyle(.black)
                                .frame(minHeight: 42)
                                .disabled(account.isConnecting)
                                Button(account.isConnecting ? "Connecting…" : "Continue with Google") {
                                    Task { await platform.connect() }
                                }
                                .buttonStyle(QuietButtonStyle(expands: false))
                                .disabled(account.isConnecting)
                            }
                            if let accountError = account.errorMessage,
                               platform.receipt.failure == nil {
                                Text(accountError)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.caution)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if !account.isSignedIn {
                                Text("Anchor stays fully usable without the Hub. Connect only if you want finished session summaries visible there.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Storage", subtitle: storeKind.storageDescription)
                        labelled("Goals", "\(goals.count)")
                        #if os(macOS)
                        labelled("Database", AnchorStore.storeURL().path)
                        #endif
                    }
                }

                #if os(macOS)
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Talk to your data", subtitle: "Anchor ships an MCP server")
                        Text("Register it once and Codex or another MCP client can answer questions like “what broke my focus most this month?” directly against your history — locally, read-only.")
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
                #endif
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

    private func hubStatus(platform: AnchorPlatformSync, signedIn: Bool) -> String {
        if platform.isSyncing { return "Syncing now" }
        if platform.receipt.failure != nil { return "Needs attention" }
        guard signedIn else { return "Not connected" }
        if platform.pendingCount > 0 { return "Waiting to sync" }
        return "Up to date"
    }

    private func lastSyncText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    #if os(macOS)
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
    #endif
}

private struct ProjectBillingRow: View {
    @Environment(\.anchorTheme) private var theme
    @Bindable var project: Project
    let save: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: project.symbolName)
                .foregroundStyle(AnchorTheme.tint(project.tintIndex))
            Text(project.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.xs)
            TextField("USD", text: $project.currencyCode)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .onSubmit(save)
            TextField("0", value: $project.hourlyRate, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .onSubmit(save)
            Text("/ hour")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.vertical, Space.xxs)
    }
}
#endif
