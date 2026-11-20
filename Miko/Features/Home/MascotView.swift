import SwiftUI
import UIKit

/// Displays the illustrated app mascot. The mood-ready API lets future
/// emotion assets be added without changing the screens that use it.
struct MascotView: View {
    enum Mood {
        case wave
        case cheer
        case teacher
        case sad
        case wrong
        case listening
    }

    let mood: Mood
    let size: CGFloat

    init(mood: Mood, size: CGFloat = 140) {
        self.mood = mood
        self.size = size
    }

    private var systemName: String {
        switch mood {
        case .wave:  return "bird.fill"
        case .cheer: return "bird.fill"
        case .teacher: return "graduationcap.fill"
        case .sad: return "heart.slash.fill"
        case .wrong: return "xmark.circle.fill"
        case .listening: return "headphones"
        }
    }

    private var assetName: String {
        switch mood {
        case .wave: return "Mascot"
        case .cheer: return "MascotCheer"
        case .teacher: return "MascotTeacher"
        case .sad: return "MascotSad"
        case .wrong: return "MascotWrong"
        case .listening: return "MascotListening"
        }
    }

    var body: some View {
        Group {
            if let mascotImage = UIImage(named: assetName) {
                Image(uiImage: mascotImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [TDColor.mint, TDColor.white],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size * 0.86, height: size * 0.86)

                    Circle()
                        .stroke(TDColor.primary, lineWidth: 3)
                        .frame(width: size * 0.86, height: size * 0.86)

                    Image(systemName: systemName)
                        .font(.system(size: max(28, size * 0.37), weight: .bold))
                        .foregroundStyle(TDColor.primaryDark)
                        .offset(y: mood == .wave ? -2 : 4)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rounded speech bubble pointing down-left toward the mascot.
struct SpeechBubble: View {
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(TDTypography.cardTitle)
                .foregroundStyle(TDColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TDSpacing.l)
                .padding(.vertical, TDSpacing.m)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: TDCornerRadius.card)
                        .fill(TDColor.surface)
                )
                .tdShadow(TDShadow.soft)

            // Tail
            Triangle()
                .fill(TDColor.surface)
                .frame(width: 22, height: 14)
                .offset(x: -36, y: -1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
