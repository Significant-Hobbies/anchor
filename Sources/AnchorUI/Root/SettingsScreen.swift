// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Small on purpose: what the app is doing with your data and the few choices
/// that change how Anchor feels. No preferences that change the product's mind
/// for you.
public struct SettingsScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.anchorPlatformSync) private var platform
    @Query private var goals: [Goal]
    @Query(sort: \AnchorPreferences.updatedAt, order: .reverse)
    private var preferences: [AnchorPreferences]
    @State private var detail: Detail?
    @State private var appearanceSaveError: String?
    private let storeKind: AnchorStore.StoreKind
    private let onShowOnboarding: (() -> Void)?
    #if os(macOS) || os(iOS)
    private let remindersCoordinator: RemindersSyncCoordinator
    @ObservedObject private var calendarCoordinator: CalendarSyncCoordinator
    #endif

    public init(
        storeKind: AnchorStore.StoreKind = .persistent,
        onShowOnboarding: (() -> Void)? = nil,
        remindersCoordinator: RemindersSyncCoordinator = RemindersSyncCoordinator(),
        calendarCoordinator: CalendarSyncCoordinator = CalendarSyncCoordinator()
    ) {
        self.storeKind = storeKind
        self.onShowOnboarding = onShowOnboarding
        #if os(macOS) || os(iOS)
        self.remindersCoordinator = remindersCoordinator
        self.calendarCoordinator = calendarCoordinator
        #endif
    }

    private enum Detail: String, Identifiable {
        case calendar = "Google Calendar"
        case projects = "Projects & tags"
        case patterns = "Patterns and replacements"
        case privacy = "Account and privacy"
        case data = "Data & continuity"

        var id: Self { self }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                #if os(macOS)
                Text("Settings").font(.largeTitle.weight(.semibold))
                #endif
                Card(padding: Space.md) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("Appearance")
                                Spacer(minLength: Space.md)
                                appearancePicker.fixedSize()
                            }
                            VStack(alignment: .leading) {
                                Text("Appearance")
                                appearancePicker
                            }
                        }
                        if let appearanceSaveError {
                            Text(appearanceSaveError).font(.caption).foregroundStyle(theme.negative)
                        }
                        Divider()
                        PlannerStartReminderSettings(compact: true)
                        Divider()
                        RemindersSettings(coordinator: remindersCoordinator)
                        Divider()
                        HStack {
                            Text("Google Calendar")
                            Spacer()
                            Button(calendarActionTitle, action: openCalendars)
                                .disabled(calendarCoordinator.isConnecting)
                                .accessibilityIdentifier("anchor.settings.calendars")
                        }
                        if let issue = calendarCoordinator.connectionIssue {
                            Text(issue).font(.caption).foregroundStyle(theme.caution)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("More settings").font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textSecondary).padding(.bottom, Space.xs)
                    detailRow(.projects).accessibilityIdentifier("anchor.settings.manage-metadata")
                    Divider()
                    detailRow(.patterns).accessibilityIdentifier("anchor.settings.patterns")
                    Divider()
                    detailRow(.privacy)
                    Divider()
                    detailRow(.data)
                    if let onShowOnboarding {
                        Divider()
                        Button(action: onShowOnboarding) {
                            rowLabel("Replay onboarding", symbol: "arrow.counterclockwise")
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .sheet(item: $detail) { selected in
            switch selected {
            case .projects:
                MetadataLibraryEditor().anchorTheme()
            case .patterns:
                BehaviorProfileEditor().anchorTheme()
            default:
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.lg) {
                            switch selected {
                            case .calendar:
                                CalendarSettings(coordinator: calendarCoordinator, inSheet: true)
                            case .privacy:
                                hubPreferences
                                privacyPreferences
                            case .data:
                                dataPreferences
                            default:
                                EmptyView()
                            }
                        }.padding(Space.lg).frame(maxWidth: 680)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle(selected.rawValue)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { detail = nil }
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 560)
                #endif
                .anchorTheme()
            }
        }
    }

    private var appearancePicker: some View {
        Picker("Appearance", selection: appearanceBinding) {
            ForEach(AnchorAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Appearance")
        .accessibilityHint(appearanceScopeLabel)
        .accessibilityIdentifier("anchor.settings.appearance")
    }

    private var calendarActionTitle: String {
        if calendarCoordinator.isConnecting { return "Connecting…" }
        if !calendarCoordinator.isConfigured { return "Availability" }
        return calendarCoordinator.accounts.isEmpty ? "Connect account" : "Manage accounts"
    }

    private func openCalendars() {
        detail = .calendar
        if calendarCoordinator.isConfigured && calendarCoordinator.accounts.isEmpty {
            Task { await calendarCoordinator.connect() }
        }
    }

    private func detailRow(_ destination: Detail) -> some View {
        Button { detail = destination } label: { rowLabel(destination.rawValue) }
            .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, symbol: String = "chevron.right") -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: symbol).font(.caption.weight(.medium)).foregroundStyle(theme.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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

    private var dataPreferences: some View {
        PreferenceGroup("Data & continuity", subtitle: storeKind.storageDescription) {
            PreferenceInfoRow(
                systemImage: appearanceContinuitySymbol,
                title: "Anchor data",
                detail: storageContinuitySummary
            )

            PreferenceDivider()
            PreferenceInfoRow(systemImage: "circle.lefthalf.filled", title: "Appearance",
                              detail: appearanceExplanation + " " + appearanceContinuityLabel)

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
        if let platform {
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

}

#endif
