#if !os(watchOS)
import AnchorCore
import AuthenticationServices
import SwiftUI

enum HubAccountLayout {
    static let controlMaxWidth: CGFloat = 340
    static let providerMarkSize: CGFloat = 16
}

/// The single account experience shared by onboarding and Settings.
/// Product surfaces supply their own surrounding layout; provider behavior,
/// privacy language, and connection states stay identical on Mac and iPhone.
public struct HubAccountPanel: View {
    public enum Presentation {
        case onboarding
        case settings
    }

    @Environment(\.anchorTheme) private var theme
    private let platform: AnchorPlatformSync?
    private let presentation: Presentation

    public init(
        platform: AnchorPlatformSync?,
        presentation: Presentation
    ) {
        self.platform = platform
        self.presentation = presentation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if presentation == .settings {
                accountIntroduction
                Divider().overlay(theme.hairline)
            } else {
                Text("WHAT THE HUB RECEIVES")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(theme.textTertiary)
            }
            privacyBoundary
            Divider().overlay(theme.hairline)
            accountState
        }
        .accessibilityElement(children: .contain)
    }

    private var accountIntroduction: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: isSignedIn ? "person.crop.circle.badge.checkmark" : "rectangle.3.group.bubble")
                .font(.title3.weight(.medium))
                .foregroundStyle(isSignedIn ? theme.positive : theme.textPrimary)
                .frame(width: 42, height: 42)
                .background(theme.surfaceRaised, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(isSignedIn ? "Connected to your Hub" : "Bring Anchor into your Hub")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(introductionCopy)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var introductionCopy: String {
        if isSignedIn {
            return presentation == .onboarding
                ? "Your finished focus sessions can now join the rest of your Significant Hobbies."
                : "Anchor can share finished-session summaries with your Significant Hobbies account."
        }
        return "Create or sign in to one Significant Hobbies account to carry finished focus summaries into the Hub."
    }

    private var privacyBoundary: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            boundaryRow(
                "Hub receives only the finished session’s goal, timing, outcome, and interruption count.",
                symbol: "checkmark.circle"
            )
            boundaryRow(
                "Distraction notes, schedules, reflections, and behavior choices never enter Hub.",
                symbol: "lock.shield"
            )
        }
    }

    private func boundaryRow(_ copy: String, symbol: String) -> some View {
        Label(copy, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var accountState: some View {
        if let platform, let account = platform.account {
            if account.isSignedIn {
                connectedState(platform: platform)
            } else {
                signedOutState(platform: platform)
            }
        } else {
            Label(
                "Hub accounts are unavailable in this build. Anchor still works fully on this device.",
                systemImage: "iphone.and.arrow.forward"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("anchor.hub.unavailable")
        }
    }

    private func connectedState(platform: AnchorPlatformSync) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Label(platform.account?.session?.email ?? "Personal account", systemImage: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.positive)
                .accessibilityIdentifier("anchor.hub.connected")

            if presentation == .settings {
                VStack(spacing: Space.xxs) {
                    labelled("Hub status", statusText(platform))
                    labelled("Waiting locally", "\(platform.pendingCount)")
                    labelled("Last successful sync", lastSyncText(platform.receipt.lastSuccessfulAt))
                }

                if let failure = platform.receipt.failure {
                    Label(
                        failure.explanation(pendingCount: platform.pendingCount),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.caution)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.sm) { connectedActions(platform) }
                    VStack(alignment: .leading, spacing: Space.sm) { connectedActions(platform) }
                }
            } else {
                Text(platform.isSyncing ? "Finishing your first sync…" : "You are ready to continue.")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func connectedActions(_ platform: AnchorPlatformSync) -> some View {
        Button(platform.isSyncing ? "Syncing…" : "Sync now") {
            Task { await platform.synchronize(announcing: true) }
        }
        .buttonStyle(QuietButtonStyle(expands: false))
        .disabled(platform.isSyncing)
        .accessibilityIdentifier("anchor.hub.sync")

        Button("Sign out") {
            Task { await platform.disconnect() }
        }
        .buttonStyle(QuietButtonStyle(expands: false))
        .accessibilityIdentifier("anchor.hub.sign-out")
    }

    @ViewBuilder
    private func signedOutState(platform: AnchorPlatformSync) -> some View {
        if let account = platform.account {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Choose an account provider")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textTertiary)

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
                .signInWithAppleButtonStyle(theme.isDark ? .white : .black)
                .frame(maxWidth: HubAccountLayout.controlMaxWidth, minHeight: 44)
                .frame(maxWidth: .infinity)
                .clipShape(.capsule)
                .disabled(account.isConnecting)
                .accessibilityIdentifier("anchor.hub.sign-in-apple")

                Button {
                    Task { await platform.connect() }
                } label: {
                    HStack(spacing: Space.xs) {
                        if account.isConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image("GoogleSignInMark")
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: HubAccountLayout.providerMarkSize,
                                    height: HubAccountLayout.providerMarkSize
                                )
                                .accessibilityHidden(true)
                        }
                        Text(account.isConnecting ? "Connecting…" : "Continue with Google")
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .frame(maxWidth: HubAccountLayout.controlMaxWidth)
                .frame(maxWidth: .infinity)
                .disabled(account.isConnecting)
                .accessibilityIdentifier("anchor.hub.sign-in-google")

                if let accountError = account.errorMessage, platform.receipt.failure == nil {
                    Label(accountError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("anchor.hub.account-error")
                }
            }
        }
    }

    private var isSignedIn: Bool {
        platform?.account?.isSignedIn == true
    }

    private func statusText(_ platform: AnchorPlatformSync) -> String {
        if platform.isSyncing { return "Syncing now" }
        if platform.receipt.failure != nil { return "Needs attention" }
        if platform.pendingCount > 0 { return "Waiting to sync" }
        return "Up to date"
    }

    private func lastSyncText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.textTertiary)
            Spacer(minLength: Space.sm)
            Text(value)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}
#endif
