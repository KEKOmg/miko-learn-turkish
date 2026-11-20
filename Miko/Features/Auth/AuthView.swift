import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AuthMode
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case email
        case password
    }

    init(initialMode: AuthMode = .signIn) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        Group {
            if case .passwordResetRequired = authStore.state {
                PasswordResetView()
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: TDSpacing.l) {
                            hero

                            if case .confirmationRequired(let address) = authStore.state {
                                confirmationView(address: address)
                            } else if case .passwordRecoverySent(let address) = authStore.state {
                                recoverySentView(address: address)
                            } else {
                                form
                            }
                        }
                        .padding(.horizontal, TDSpacing.l)
                        .padding(.vertical, TDSpacing.l)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(TDColor.background)
                    .navigationTitle("auth.title")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("auth.close") { dismiss() }
                        }
                    }
                }
            }
        }
        .onChange(of: mode) { _, _ in authStore.clearError() }
    }

    private var hero: some View {
        VStack(spacing: TDSpacing.m) {
            ZStack {
                Circle()
                    .fill(TDColor.primary.opacity(0.13))
                    .frame(width: 92, height: 92)

                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(TDColor.primary)
            }

            Text("auth.hero.title")
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("auth.hero.subtitle")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: TDSpacing.m) {
            Picker("auth.mode", selection: $mode) {
                Text("auth.signIn").tag(AuthMode.signIn)
                Text("auth.signUp").tag(AuthMode.signUp)
            }
            .pickerStyle(.segmented)

            VStack(spacing: TDSpacing.m) {
                if mode == .signUp {
                    authField(icon: "person.fill") {
                        TextField("auth.username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }
                    }
                }

                authField(icon: "envelope.fill") {
                    TextField("auth.email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                authField(icon: "lock.fill") {
                    SecureField("auth.password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                }
            }

            if let message = authStore.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(TDTypography.caption)
                    .foregroundStyle(TDColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("auth.error")
            }

            Button(action: submit) {
                Group {
                    if authStore.state == .loading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(mode == .signIn ? "auth.action.signIn" : "auth.action.signUp")
                            .font(TDTypography.button)
                    }
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: TDCornerRadius.button)
                        .fill(TDColor.primary)
                )
            }
            .buttonStyle(TDPressButtonStyle())
            .disabled(authStore.state == .loading)
            .accessibilityIdentifier("auth.submit")

            if mode == .signIn {
                Button("auth.forgotPassword") {
                    focusedField = nil
                    Task { await authStore.requestPasswordReset(email: email) }
                }
                .font(TDTypography.caption)
                .foregroundStyle(TDColor.primary)
                .disabled(authStore.state == .loading)
                .accessibilityIdentifier("auth.forgotPassword")
            }

            Label("auth.security", systemImage: "lock.shield.fill")
                .font(TDTypography.caption)
                .foregroundStyle(TDColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func authField<Content: View>(
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: TDSpacing.m) {
            Image(systemName: icon)
                .foregroundStyle(TDColor.primary)
                .frame(width: 22)
            content()
                .font(TDTypography.body)
        }
        .padding(.horizontal, TDSpacing.m)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                .fill(TDColor.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                .stroke(TDColor.disabled.opacity(0.65), lineWidth: 1)
        }
    }

    private func confirmationView(address: String) -> some View {
        TDCard {
            VStack(spacing: TDSpacing.m) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(TDColor.success)

                Text("auth.confirmation.title")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)

                Text(String(localized: "auth.confirmation.message \(address)"))
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                    .multilineTextAlignment(.center)

                TDButton("auth.signIn", style: .primaryCompact) {
                    mode = .signIn
                    authStore.returnToSignIn()
                }

                TDButton("auth.confirmation.done", style: .secondary) {
                    dismiss()
                }
            }
        }
    }

    private func recoverySentView(address: String) -> some View {
        TDCard {
            VStack(spacing: TDSpacing.m) {
                Image(systemName: "key.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(TDColor.success)

                Text("auth.recovery.sent.title")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)

                Text(String(localized: "auth.recovery.sent.message \(address)"))
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                    .multilineTextAlignment(.center)

                TDButton("auth.recovery.back", style: .secondary) {
                    mode = .signIn
                    authStore.returnToSignIn()
                }
            }
        }
    }

    private func submit() {
        focusedField = nil
        Task {
            let succeeded = await authStore.submit(
                mode: mode,
                username: username,
                email: email,
                password: password
            )
            if succeeded, authStore.user != nil {
                dismiss()
            }
        }
    }
}

struct PasswordResetView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: TDSpacing.l) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(TDColor.primary)

                Text("auth.reset.title")
                    .font(TDTypography.sectionTitle)
                    .foregroundStyle(TDColor.textPrimary)

                Text("auth.reset.subtitle")
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                    .multilineTextAlignment(.center)

                SecureField("auth.reset.newPassword", text: $password)
                    .textContentType(.newPassword)
                    .padding(.horizontal, TDSpacing.m)
                    .frame(minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: TDCornerRadius.smallCard).fill(TDColor.surface))

                SecureField("auth.reset.confirmPassword", text: $confirmation)
                    .textContentType(.newPassword)
                    .padding(.horizontal, TDSpacing.m)
                    .frame(minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: TDCornerRadius.smallCard).fill(TDColor.surface))

                if let message = authStore.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                TDButton("auth.reset.action") {
                    Task {
                        if await authStore.updatePassword(password, confirmation: confirmation) {
                            dismiss()
                        }
                    }
                }

                TDButton("auth.reset.cancel", style: .secondary) {
                    authStore.cancelPasswordReset()
                }

                Spacer()
            }
            .padding(TDSpacing.l)
            .background(TDColor.background)
        }
    }
}
