import SwiftUI

/// Reusable button styles adhering to the Miko design system.
struct TDButton: View {
    let title: LocalizedStringKey
    let style: Style
    let action: () -> Void

    enum Style {
        case primary
        case primaryCompact
        case secondary
        case destructive
        case disabled

        var isDisabled: Bool {
            if case .disabled = self { return true }
            return false
        }
    }

    init(
        _ title: LocalizedStringKey,
        style: Style = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: { if !style.isDisabled { action() } }) {
            Text(title)
                .font(TDTypography.button)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: TDCornerRadius.button)
                        .fill(backgroundColor)
                )
                .tdShadow(TDShadow.soft)
                .contentShape(Rectangle())
        }
        .disabled(style.isDisabled)
        .buttonStyle(TDPressButtonStyle())
    }

    private var backgroundColor: Color {
        switch style {
        case .primary, .primaryCompact:
            return TDColor.primary
        case .secondary:
            return TDColor.secondarySurface
        case .destructive:
            return TDColor.error
        case .disabled:
            return TDColor.disabled
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .primaryCompact, .destructive:
            return .white
        case .secondary:
            return TDColor.textPrimary
        case .disabled:
            return TDColor.disabledText
        }
    }

    private var height: CGFloat {
        switch style {
        case .primary:           return 58
        case .primaryCompact:    return 48
        case .secondary:         return 52
        case .destructive:       return 58
        case .disabled:          return 58
        }
    }
}

/// Press-scale button style. Replaces the previous `simultaneousGesture`
/// approach, which could swallow taps on buttons that appear dynamically
/// (e.g. the Continue button shown after Check). Using a `ButtonStyle` keeps
/// the same press visual while leaving tap delivery to SwiftUI's standard
/// button recognizer.
struct TDPressButtonStyle: ButtonStyle {
    @Environment(\.tdReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6),
                value: configuration.isPressed
            )
    }
}

private struct TDReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tdReduceMotion: Bool {
        get { self[TDReduceMotionKey.self] }
        set { self[TDReduceMotionKey.self] = newValue }
    }
}
