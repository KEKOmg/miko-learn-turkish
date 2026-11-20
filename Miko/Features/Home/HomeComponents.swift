import SwiftUI

/// Top stats strip for the Home screen: streak, XP, hearts.
///
/// Uses the existing design-system pill components (`TDStreakView`,
/// `TDXPView`, `TDHeartView`) so styling stays consistent.
struct StatsHeader: View {
    let stats: UserStatsSnapshot

    var body: some View {
        HStack(spacing: TDSpacing.s) {
            TDStreakView(days: stats.streakDays)
                .accessibilityIdentifier("home.streak")
            TDXPView(xp: stats.xp)
                .accessibilityIdentifier("home.xp")
            Spacer(minLength: 0)
            TDHeartView(total: stats.heartsTotal, remaining: stats.heartsRemaining)
                .accessibilityIdentifier("home.hearts")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Daily goal card: shows today's XP progress toward the goal with a
/// progress bar and a reached/not-reached label.
struct DailyGoalCard: View {
    let stats: UserStatsSnapshot

    var body: some View {
        TDCard {
            VStack(alignment: .leading, spacing: TDSpacing.m) {
                HStack {
                    Image(systemName: "target")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(TDColor.primary)
                    Text("home.dailyGoal.title")
                        .font(TDTypography.cardTitle)
                        .foregroundStyle(TDColor.textPrimary)
                    Spacer()
                    Text("\(stats.dailyGoalEarned) / \(stats.dailyGoalXP) XP")
                        .font(TDTypography.secondary)
                        .fontWeight(.bold)
                        .foregroundStyle(TDColor.textSecondary)
                        .accessibilityIdentifier("home.dailyGoal.value")
                }

                TDProgressBar(
                    progress: stats.dailyGoalProgress,
                    tint: stats.isDailyGoalReached ? TDColor.success : TDColor.primary
                )
                .accessibilityIdentifier("home.dailyGoal.progress")

                Text(stats.isDailyGoalReached
                     ? "home.dailyGoal.reached"
                     : "home.dailyGoal.keepGoing")
                    .font(TDTypography.secondary)
                    .foregroundStyle(stats.isDailyGoalReached ? TDColor.success : TDColor.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Claimable daily reward chest. Reaching the daily XP goal unlocks a gem
/// reward once per calendar day.
struct XPRewardCard: View {
    @Environment(\.tdReduceMotion) private var reduceMotion

    let canClaim: Bool
    let isClaimed: Bool
    let rewardGems: Int
    let xpRemaining: Int
    let onClaim: () -> Void
    @State private var isOpening = false
    @State private var showReward = false

    var body: some View {
        TDCard {
            VStack(alignment: .leading, spacing: TDSpacing.m) {
                HStack(spacing: TDSpacing.m) {
                    RewardChestView(
                        isOpen: isClaimed || isOpening,
                        isCelebrating: showReward,
                        isAvailable: canClaim
                    )
                    .frame(width: 78, height: 76)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: TDSpacing.xs) {
                        Text("home.xpReward.title")
                            .font(TDTypography.cardTitle)
                            .foregroundStyle(TDColor.textPrimary)

                        if isClaimed {
                            Text("home.xpReward.claimed")
                                .font(TDTypography.secondary)
                                .foregroundStyle(TDColor.success)
                        } else if canClaim {
                            Text(String(localized: "home.xpReward.ready \(rewardGems)"))
                                .font(TDTypography.secondary)
                                .foregroundStyle(TDColor.textSecondary)
                        } else {
                            Text(String(localized: "home.xpReward.remaining \(xpRemaining)"))
                                .font(TDTypography.secondary)
                                .foregroundStyle(TDColor.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if canClaim {
                    Button(action: openChest) {
                        Label(
                            String(localized: "home.xpReward.claim \(rewardGems)"),
                            systemImage: "diamond.fill"
                        )
                        .font(TDTypography.button)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: TDCornerRadius.button)
                                .fill(TDColor.primary)
                        )
                    }
                    .buttonStyle(TDPressButtonStyle())
                    .disabled(isOpening)
                    .accessibilityIdentifier("home.xpReward.claim")
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showReward {
                MascotView(mood: .cheer, size: 88)
                    .offset(x: -TDSpacing.s, y: -TDSpacing.m)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func openChest() {
        guard !isOpening else { return }
        guard !reduceMotion else {
            onClaim()
            return
        }

        withAnimation(.spring(response: 0.48, dampingFraction: 0.62)) {
            isOpening = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.18)) {
            showReward = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
            onClaim()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showReward = false
                    isOpening = false
                }
            }
        }
    }
}

private struct RewardChestView: View {
    let isOpen: Bool
    let isCelebrating: Bool
    let isAvailable: Bool

    private let particleOffsets: [CGSize] = [
        CGSize(width: -27, height: -31), CGSize(width: -10, height: -43),
        CGSize(width: 12, height: -42), CGSize(width: 29, height: -27),
        CGSize(width: -34, height: -12), CGSize(width: 34, height: -8)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(TDColor.gold.opacity(isAvailable || isOpen ? 0.28 : 0.1))
                .scaleEffect(isCelebrating ? 1.18 : 1)

            ForEach(Array(particleOffsets.enumerated()), id: \.offset) { index, offset in
                Image(systemName: index.isMultiple(of: 2) ? "diamond.fill" : "sparkle")
                    .font(.system(size: index.isMultiple(of: 2) ? 9 : 11, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2) ? TDColor.primary : TDColor.gold)
                    .offset(isCelebrating ? offset : .zero)
                    .scaleEffect(isCelebrating ? 1 : 0.15)
                    .opacity(isCelebrating ? 1 : 0)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "D99036"), Color(hex: "9D5426")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 55, height: 34)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(TDColor.gold)
                            .frame(height: 5)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "713A1D"), lineWidth: 2)
                    }

                RoundedRectangle(cornerRadius: 5)
                    .fill(TDColor.gold)
                    .frame(width: 16, height: 18)
                    .overlay {
                        Image(systemName: isOpen ? "checkmark" : "diamond.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color(hex: "79451E"))
                    }
            }
            .offset(y: 13)

            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "F2AC48"), Color(hex: "B9672A")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 55, height: 23)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TDColor.gold)
                        .frame(height: 5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "713A1D"), lineWidth: 2)
                }
                .rotationEffect(.degrees(isOpen ? -17 : 0), anchor: .bottomLeading)
                .offset(x: isOpen ? 2 : 0, y: isOpen ? -19 : -11)
        }
        .shadow(color: TDColor.gold.opacity(isCelebrating ? 0.7 : 0), radius: 12)
    }
}
