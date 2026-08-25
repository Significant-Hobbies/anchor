// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
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
    @Environment(\.anchorWorkspaceMaxWidth) private var workspaceMaxWidth
    @Environment(\.modelContext) private var context
    @Environment(\.anchorPlatformSync) private var platform
    @Query private var goals: [Goal]
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query private var behaviorProfiles: [BehaviorProfile]
    @Query(sort: \AnchorPreferences.updatedAt, order: .reverse)
    private var preferences: [AnchorPreferences]
    @State private var showsBehaviorProfile = false
    @State private var appearanceSaveError: String?
    #if os(macOS)
    @State private var didCopy = false
    #endif
    private let storeKind: AnchorStore.StoreKind
    private let onShowOnboarding: (() -> Void)?

    public init(
        storeKind: AnchorStore.StoreKind = .persistent,
        onShowOnboarding: (() -> Void)? = nil
    ) {
        self.storeKind = storeKind
        self.onShowOnboarding = onShowOnboarding
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
            VStack(alignment: .leading, spacing: Space.xl) {
                SettingsIntro()

                if workspaceMaxWidth >= 900 {
                    HStack(alignment: .top, spacing: Space.lg) {
                        primarySettingsColumn
                        secondarySettingsColumn
                    }
                } else {
                    VStack(spacing: Space.lg) {
                        primarySettingsColumn
                        secondarySettingsColumn
                    }
                }
            }
            .padding(Space.lg)
            #if os(macOS)
            .frame(maxWidth: min(workspaceMaxWidth, 1_040))
            #else
            .frame(maxWidth: 680)
            #endif
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .sheet(isPresented: $showsBehaviorProfile) {
            BehaviorProfileEditor().anchorTheme()
        }
    }

    private var primarySettingsColumn: some View {
        VStack(spacing: Space.lg) {
            personalPreferences
            projectPreferences
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var secondarySettingsColumn: some View {
        VStack(spacing: Space.lg) {
            hubPreferences
            privacyPreferences
            dataPreferences
            #if os(macOS)
            advancedPreferences
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var personalPreferences: some View {
        PreferenceGroup("Personal", subtitle: "The choices that change how Anchor feels") {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(theme.textSecondary.opacity(0.10), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance")
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.textPrimary)
                        Text(appearanceScopeLabel)
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(AnchorAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minHeight: 44)
                .accessibilityLabel("Appearance")
                .accessibilityIdentifier("anchor.settings.appearance")

                Text(appearanceExplanation)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(appearanceContinuityLabel, systemImage: appearanceContinuitySymbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.textTertiary)

                if let appearanceSaveError {
                    Label(appearanceSaveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.negative)
                }
            }
            .padding(Space.md)

            if let onShowOnboarding {
                PreferenceDivider()
                PreferenceActionRow(
                    systemImage: "sparkles.rectangle.stack",
                    title: "View onboarding",
                    detail: "Replay the plan, habit, focus, and interruption walkthrough.",
                    action: onShowOnboarding
                )
            }

            PreferenceDivider()
            PreferenceActionRow(
                systemImage: "arrow.triangle.branch",
                title: "Edit patterns and alternatives",
                detail: behaviorProfileSummary
            ) { showsBehaviorProfile = true }
        }
    }

    private var behaviorProfileSummary: String {
        let profile = behaviorProfiles.first
        let patterns = profile?.selectedPatterns.count ?? 0
        let directions = profile?.desiredDirections.count ?? 0
        if patterns == 0 && directions == 0 {
            return "Choose what tends to pull you and what you want that time to become."
        }
        return "\(patterns) pattern\(patterns == 1 ? "" : "s") · \(directions) direction\(directions == 1 ? "" : "s")"
    }

    private var privacyPreferences: some View {
        let availability = TaggingService.availability
        return PreferenceGroup("Private by design", subtitle: "What Anchor can observe—and what it never will") {
            PreferenceInfoRow(
                systemImage: availability.isAvailable ? "sparkles" : "checkmark.shield",
                title: "On-device intelligence",
                detail: availability.explanation,
                tint: availability.isAvailable ? theme.textPrimary : theme.caution
            )
            PreferenceDivider()
            PreferenceInfoRow(
                systemImage: "hand.raised",
                title: "Distraction notes stay here",
                detail: "Grouping uses Apple’s on-device model or built-in rules. The note never enters Hub summaries."
            )
            #if os(macOS)
            PreferenceDivider()
            PreferenceInfoRow(
                systemImage: "desktopcomputer",
                title: "Computer activity",
                detail: "Only aggregate active, tracked, and away seconds—never apps, windows, websites, keys, or pointer locations."
            )
            #endif
        }
    }

    private var projectPreferences: some View {
        PreferenceGroup("Projects & rates", subtitle: "Optional context for paid or client work") {
            if projects.isEmpty {
                PreferenceInfoRow(
                    systemImage: "briefcase",
                    title: "No project rates yet",
                    detail: "Create a project from Focus, then set its hourly rate here."
                )
            } else {
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    ProjectBillingRow(project: project) {
                        project.hourlyRate = max(0, project.hourlyRate)
                        project.currencyCode = project.currencyCode
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .uppercased()
                        if project.currencyCode.isEmpty { project.currencyCode = "USD" }
                        try context.save()
                    }
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
                    if index < projects.count - 1 { PreferenceDivider() }
                }
            }
        }
    }

    private var dataPreferences: some View {
        PreferenceGroup("Data & continuity", subtitle: storeKind.storageDescription) {
            PreferenceInfoRow(
                systemImage: appearanceContinuitySymbol,
                title: "Anchor data",
                detail: storageContinuitySummary
            )

            PreferenceDivider()
            PreferenceInfoRow(
                systemImage: "internaldrive",
                title: "Local library",
                detail: "\(goals.count) goal\(goals.count == 1 ? "" : "s") in this store."
            )
        }
    }

    @ViewBuilder
    private var hubPreferences: some View {
        if let platform, platform.account != nil {
            PreferenceGroup(
                "Significant Hobbies Hub",
                subtitle: "One optional account across the family"
            ) {
                HubAccountPanel(platform: platform, presentation: .settings)
                    .padding(Space.md)
            }
        }
    }

    private var storageContinuitySummary: String {
        switch storeKind {
        case .persistent:
            "Private iCloud continuity across your Apple devices."
        case .localOnly:
            "This unsigned build stores data on this device only."
        case .inMemory:
            "Temporary data for this session."
        }
    }

    #if os(macOS)
    private var advancedPreferences: some View {
        PreferenceGroup("Local tools", subtitle: "Optional ways to work with your own data") {
            PreferenceInfoRow(
                systemImage: "terminal",
                title: "Talk to your data",
                detail: "Register Anchor’s read-only MCP server with Codex or another local client."
            )
            PreferenceDivider()
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(mcpCommand)
                    .font(.system(.caption, design: .monospaced))
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
            .padding(Space.md)
        }
    }
    #endif

    private var selectedAppearance: AnchorAppearance {
        AnchorPreferencesPolicy.appearance(in: preferences)
    }

    private var appearanceBinding: Binding<AnchorAppearance> {
        Binding(
            get: { selectedAppearance },
            set: { updateAppearance($0) }
        )
    }

    private var appearanceExplanation: String {
        switch selectedAppearance {
        case .system:
            switch storeKind {
            case .persistent:
                "Follows each device’s system setting, so Mac and iPhone may intentionally differ."
            case .localOnly:
                "Follows this device’s system setting."
            case .inMemory:
                "Previews this device’s system setting for this session."
            }
        case .light:
            appearanceScoped("Uses warm paper")
        case .dark:
            appearanceScoped("Uses the charcoal focus canvas")
        }
    }

    private var appearanceScopeLabel: String {
        switch storeKind {
        case .persistent: "One choice across your Anchor devices"
        case .localOnly: "Choose how Anchor looks on this device"
        case .inMemory: "Preview Anchor’s appearance for this session"
        }
    }

    private func appearanceScoped(_ description: String) -> String {
        switch storeKind {
        case .persistent: "\(description) across your Anchor devices."
        case .localOnly: "\(description) on this device."
        case .inMemory: "\(description) for this session."
        }
    }

    private var appearanceContinuityLabel: String {
        switch storeKind {
        case .persistent:
            "Saved privately with your Anchor data in iCloud"
        case .localOnly:
            "This build stores appearance on this device only"
        case .inMemory:
            "Temporary for this session"
        }
    }

    private var appearanceContinuitySymbol: String {
        switch storeKind {
        case .persistent: "icloud"
        case .localOnly: "iphone.and.arrow.forward"
        case .inMemory: "clock"
        }
    }

    private func updateAppearance(_ appearance: AnchorAppearance) {
        let preference: AnchorPreferences
        if let latest = AnchorPreferencesPolicy.latest(in: preferences) {
            preference = latest
        } else {
            preference = AnchorPreferences()
            context.insert(preference)
        }
        preference.appearance = appearance
        preference.updatedAt = Date()
        do {
            try context.save()
            appearanceSaveError = nil
        } catch {
            appearanceSaveError = "Anchor could not save the appearance choice. Try again."
        }
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

private struct SettingsIntro: View {
    @Environment(\.anchorTheme) private var theme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Space.xxl) {
                copy(
                    showsEyebrow: true,
                    titleFont: .system(.largeTitle, design: .rounded).weight(.semibold),
                    messageFont: .body
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                artwork.frame(width: 260)
            }
            .frame(minWidth: 620)

            VStack(alignment: .leading, spacing: Space.sm) {
                copy(
                    showsEyebrow: false,
                    titleFont: .system(.title, design: .rounded).weight(.semibold),
                    messageFont: .subheadline
                )
                artwork
                    .frame(maxWidth: 210, maxHeight: 110)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func copy(
        showsEyebrow: Bool,
        titleFont: Font,
        messageFont: Font
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if showsEyebrow {
                Text("SETTINGS")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(theme.textTertiary)
            }
            Text("Make Anchor yours")
                .font(titleFont)
                .foregroundStyle(theme.textPrimary)
            DrawnUnderline(width: 78)
            Text("Appearance, privacy, continuity, and the few choices that should stay in your hands.")
                .font(messageFont)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var artwork: some View {
        Image("FocusDoodle")
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 150)
            .accessibilityHidden(true)
    }
}

private struct ProjectBillingRow: View {
    @Environment(\.anchorTheme) private var theme
    @Bindable var project: Project
    @State private var saveFeedback: SaveFeedback?
    let save: () throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            projectIdentity

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: Space.sm) {
                    billingFields
                    saveButton
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    billingFields
                    saveButton
                }
            }

            if let saveFeedback {
                Label(saveFeedback.message, systemImage: saveFeedback.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(saveFeedback.isError ? theme.negative : theme.textSecondary)
                    .accessibilityIdentifier("anchor.settings.project-rate-feedback")
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var projectIdentity: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: project.symbolName)
                .foregroundStyle(AnchorTheme.tint(project.tintIndex))
            Text(project.name)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
        }
    }

    private var billingFields: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Currency")
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
                TextField("USD", text: $project.currencyCode)
                    .accessibilityLabel("Currency for \(project.name)")
                    .frame(minWidth: 64)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Hourly rate")
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
                HStack(spacing: Space.xxs) {
                    TextField("0", value: $project.hourlyRate, format: .number.precision(.fractionLength(0...2)))
                        .accessibilityLabel("Hourly rate for \(project.name)")
                        .frame(minWidth: 80)
                    Text("/ hour")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var saveButton: some View {
        Button("Save rate", action: commit)
            .buttonStyle(QuietButtonStyle(expands: false))
            .accessibilityLabel("Save rate for \(project.name)")
    }

    private func commit() {
        do {
            try save()
            saveFeedback = .saved
        } catch {
            saveFeedback = .failed
        }
    }

    private enum SaveFeedback {
        case saved
        case failed

        var isError: Bool { self == .failed }
        var message: String { self == .saved ? "Rate saved" : "Anchor could not save this rate. Try again." }
        var symbol: String { self == .saved ? "checkmark" : "exclamationmark.triangle.fill" }
    }
}
#endif
