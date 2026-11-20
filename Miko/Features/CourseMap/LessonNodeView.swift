import SwiftUI

/// A single rounded lesson node on the vertical learning path.
///
/// Visual states:
/// - **completed**: teal filled circle with a checkmark + star pips below.
/// - **unlocked**: white/cream filled circle with the lesson icon, teal border.
/// - **locked**: muted surface with a lock icon, no interaction.
struct LessonNodeView: View {
    let node: LessonNode
    let position: Int
    var onTap: () -> Void

    private var diameter: CGFloat { 72 }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: TDSpacing.s) {
                nodeCircle
                starsRow
                    .opacity(starsRowOpacity)
                titleText
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!node.isPlayable)
        .buttonStyle(TDPressButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("courseMap.lesson.\(node.key)")
    }

    @ViewBuilder
    private var nodeCircle: some View {
        ZStack {
            Circle()
                .fill(circleFill)
                .frame(width: diameter, height: diameter)
                .tdShadow(TDShadow.soft)

            Circle()
                .stroke(circleStroke, lineWidth: 3)
                .frame(width: diameter, height: diameter)

            circleContent
        }
    }

    @ViewBuilder
    private var circleContent: some View {
        switch node.state {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        case .unlocked:
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(TDColor.primary)
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(TDColor.disabledText)
        }
    }

    private var circleFill: Color {
        switch node.state {
        case .completed: return TDColor.primary
        case .unlocked:  return TDColor.surface
        case .locked:    return TDColor.disabled.opacity(0.5)
        }
    }

    private var circleStroke: Color {
        switch node.state {
        case .completed: return TDColor.primaryDark
        case .unlocked:  return TDColor.primary
        case .locked:    return TDColor.disabled
        }
    }

    @ViewBuilder
    private var starsRow: some View {
        let starCount: Int = {
            if case .completed(let stars, _) = node.state { return stars }
            return 0
        }()
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < starCount ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(i < starCount ? TDColor.gold : TDColor.disabled)
            }
        }
        .frame(height: 14)
    }

    private var starsRowOpacity: Double {
        if case .completed = node.state { return 1 }
        return 0
    }

    @ViewBuilder
    private var titleText: some View {
        Text(localizedTitle)
            .font(TDTypography.secondary)
            .fontWeight(.semibold)
            .foregroundStyle(node.isPlayable ? TDColor.textPrimary : TDColor.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(minHeight: 32)
    }

    private var localizedTitle: String {
        let fallbackKey = "lesson.\(node.key).title"
        let trimmedKey = node.titleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryKey = trimmedKey.isEmpty ? fallbackKey : trimmedKey
        let primaryValue = String(localized: String.LocalizationValue(primaryKey))

        if !primaryValue.isEmpty, primaryValue != primaryKey {
            return primaryValue
        }

        let fallbackValue = String(localized: String.LocalizationValue(fallbackKey))
        return fallbackValue == fallbackKey ? node.key : fallbackValue
    }

    private var accessibilityLabel: String {
        let title = localizedTitle
        switch node.state {
        case .completed(let stars, _):
            return String(localized: "courseMap.a11y.completed \(title) \(stars)")
        case .unlocked:
            return String(localized: "courseMap.a11y.unlocked \(title)")
        case .locked:
            return String(localized: "courseMap.a11y.locked \(title)")
        }
    }

    private var accessibilityHint: String {
        node.isPlayable
            ? String(localized: "courseMap.a11y.hint.playable")
            : String(localized: "courseMap.a11y.hint.locked")
    }
}

/// Curved dotted connector between consecutive lesson nodes. Purely visual.
struct LessonConnector: View {
    var direction: Direction = .right

    enum Direction { case left, right }

    var body: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(TDColor.primary.opacity(0.6))
            .frame(height: 28)
            .accessibilityHidden(true)
    }
}
