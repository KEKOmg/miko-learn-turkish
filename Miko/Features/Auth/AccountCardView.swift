import SwiftUI

struct AccountCardView: View {
    @Environment(AuthStore.self) private var authStore

    let onOpenAuth: () -> Void
    let onSync: () -> Void

    var body: some View {
        TDCard {
            switch authStore.state {
            case .signedIn(let user):
                signedInContent(user: user)
            case .loading:
                HStack(spacing: TDSpacing.m) {
                    ProgressView().tint(TDColor.primary)
                    Text("auth.account.loading")
                        .font(TDTypography.secondary)
                        .foregroundStyle(TDColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .unconfigured:
                unavailableContent
            case .signedOut, .confirmationRequired, .passwordRecoverySent, .passwordResetRequired:
                guestContent
            }
        }
        .accessibilityIdentifier("profile.account")
    }

    private func signedInContent(user: AuthUser) -> some View {
        VStack(spacing: TDSpacing.m) {
            HStack(spacing: TDSpacing.m) {
                ZStack {
                    Circle()
                        .fill(TDColor.primary.opacity(0.15))
                        .frame(width: 54, height: 54)
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(TDColor.primary)
                }

                VStack(alignment: .leading, spacing: TDSpacing.xs) {
                    Text(user.username.isEmpty ? String(localized: "auth.account.user") : user.username)
                        .font(TDTypography.cardTitle)
                        .foregroundStyle(TDColor.textPrimary)
                    Text(user.email)
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TDColor.success)
                    .accessibilityLabel("auth.account.connected")
            }

            if let error = authStore.errorMessage {
                Text(error)
                    .font(TDTypography.caption)
                    .foregroundStyle(TDColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(authStore.lastSyncDate == nil ? "auth.sync.ready" : "auth.sync.complete")
                    .font(TDTypography.caption)
                    .foregroundStyle(TDColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: TDSpacing.m) {
                Button(action: onSync) {
                    Label(
                        authStore.isSyncing ? "auth.sync.syncing" : "auth.sync.action",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(TDTypography.caption)
                    .foregroundStyle(TDColor.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: TDCornerRadius.button)
                            .fill(TDColor.secondarySurface)
                    )
                }
                .buttonStyle(TDPressButtonStyle())
                .disabled(authStore.isSyncing)

                Button {
                    Task { await authStore.signOut() }
                } label: {
                    Text("auth.signOut")
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.error)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: TDCornerRadius.button)
                                .fill(TDColor.error.opacity(0.1))
                        )
                }
                .buttonStyle(TDPressButtonStyle())
            }
        }
    }

    private var guestContent: some View {
        VStack(alignment: .leading, spacing: TDSpacing.m) {
            Label {
                Text("auth.account.guest.title")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)
            } icon: {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(TDColor.primary)
            }

            Text("auth.account.guest.message")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)

            TDButton("auth.account.open", style: .primaryCompact, action: onOpenAuth)
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: TDSpacing.s) {
            Label("auth.account.unavailable.title", systemImage: "externaldrive.badge.exclamationmark")
                .font(TDTypography.cardTitle)
                .foregroundStyle(TDColor.textPrimary)

            Text("auth.account.unavailable.message")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
    }
}
