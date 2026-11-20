import SwiftUI

/// Weekly league experience. Lifetime XP stays in the profile, while this
/// screen ranks only XP earned inside the active Monday-to-Monday season.
/// The leaderboard is rendered exclusively from server-authoritative data.
struct RankingView: View {
    private struct Player: Identifiable {
        let id: String
        let name: String
        let xp: Int
        let symbol: String
        let tint: Color
        let isCurrentUser: Bool
    }

    var isActive: Bool = true

    @Environment(AuthStore.self) private var authStore
    @Environment(\.tdReduceMotion) private var reduceMotion
    @State private var liveLeaderboard: LeagueLeaderboard?
    @State private var hasAppeared = false

    private static let palette: [(symbol: String, tint: Color)] = [
        ("sparkles", TDColor.coral),
        ("flame.fill", TDColor.warning),
        ("moon.stars.fill", Color(hex: "7868E6")),
        ("bolt.fill", TDColor.primary),
        ("heart.fill", TDColor.coral),
        ("drop.fill", Color(hex: "4F8EF7")),
        ("leaf.fill", TDColor.success),
        ("star.fill", TDColor.gold),
        ("sun.max.fill", TDColor.warning)
    ]

    private var players: [Player] {
        guard let liveLeaderboard else { return [] }
        return livePlayers(from: liveLeaderboard)
    }

    private var activeLeague: LeagueTier {
        liveLeaderboard?.league ?? .turquoise
    }

    private var promotionCount: Int {
        liveLeaderboard?.promotionCount ?? 5
    }

    private var demotionStart: Int? {
        liveLeaderboard?.demotionStart
    }

    private var isWeeklyLeague: Bool {
        liveLeaderboard?.scorePeriod == .weekly
    }

    private func livePlayers(from leaderboard: LeagueLeaderboard) -> [Player] {
        let currentID = authStore.user?.id
        return leaderboard.entries.map { entry -> Player in
            let isCurrentUser = entry.id == currentID
            let style = Self.style(for: entry.id)
            return Player(
                id: entry.id.uuidString,
                name: entry.username.isEmpty ? String(localized: "ranking.you") : entry.username,
                xp: entry.weeklyXP,
                symbol: isCurrentUser ? "person.fill" : style.symbol,
                tint: isCurrentUser ? TDColor.primary : style.tint,
                isCurrentUser: isCurrentUser
            )
        }
    }

    /// Deterministic avatar styling derived from the profile UUID, so a given
    /// player always looks the same across sessions.
    private static func style(for id: UUID) -> (symbol: String, tint: Color) {
        var hash = 5381
        for scalar in id.uuidString.unicodeScalars {
            hash = (hash &* 33 &+ Int(scalar.value)) & 0x7FFFFFFF
        }
        return palette[hash % palette.count]
    }

    private var currentRank: Int {
        (players.firstIndex(where: \.isCurrentUser) ?? 0) + 1
    }

    private var currentScoreXP: Int {
        players.first(where: \.isCurrentUser)?.xp ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TDSpacing.l) {
                leagueHero
                leagueJourney
                if liveLeaderboard != nil, !players.isEmpty {
                    if players.count >= 3 {
                        podium
                    }
                    if players.contains(where: \.isCurrentUser) {
                        currentPositionCard
                    }
                    leaderboard
                } else {
                    realDataUnavailableCard
                }
            }
            .padding(.horizontal, TDSpacing.m)
            .padding(.top, TDSpacing.m)
            .padding(.bottom, TDSpacing.xxl)
        }
        .background(TDColor.background)
        .task(id: isActive) {
            guard isActive else { return }
            await refreshLeaderboard()
            withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.78)) {
                hasAppeared = true
            }
        }
    }

    @MainActor
    private func refreshLeaderboard() async {
        guard authStore.user != nil else {
            liveLeaderboard = nil
            return
        }
        liveLeaderboard = await authStore.loadWeeklyLeague()
    }

    private var leagueHero: some View {
        VStack(spacing: TDSpacing.m) {
            HStack {
                Text(seasonStatusKey)
                    .font(TDTypography.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(TDColor.primaryDark)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(TDColor.mint))

                Spacer()

                if isWeeklyLeague {
                    Label(remainingTime, systemImage: "clock.fill")
                        .font(TDTypography.caption)
                        .foregroundStyle(Color.white.opacity(0.82))
                } else {
                    Label("ranking.realPlayers", systemImage: "person.2.fill")
                        .font(TDTypography.caption)
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }

            ZStack {
                Circle()
                    .fill(leagueAccent.opacity(0.2))
                    .frame(width: 112, height: 112)
                    .scaleEffect(hasAppeared ? 1.08 : 0.82)

                Circle()
                    .stroke(leagueAccent.opacity(0.6), lineWidth: 2)
                    .frame(width: 92, height: 92)

                Image(systemName: leagueSymbol(for: activeLeague))
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [leagueAccent, Color.white, leagueAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(hasAppeared ? 0 : -8))
            }

            VStack(spacing: TDSpacing.xs) {
                if isWeeklyLeague, let league = liveLeaderboard?.league {
                    Text(leagueNameKey(league))
                        .font(TDTypography.title)
                        .foregroundStyle(Color.white)
                } else {
                    Text(heroTitleKey)
                        .font(TDTypography.title)
                        .foregroundStyle(Color.white)
                }
                if isWeeklyLeague, let group = liveLeaderboard?.groupNumber {
                    Text(String(localized: "ranking.group \(group)"))
                        .font(TDTypography.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Text("ranking.league.subtitle")
                    .font(TDTypography.secondary)
                    .foregroundStyle(Color.white.opacity(0.76))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(TDSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: TDCornerRadius.card)
                .fill(
                    LinearGradient(
                        colors: leagueGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.white.opacity(0.08))
                        .offset(x: 12, y: -8)
                }
        )
        .tdShadow(TDShadow.elevated)
    }

    private var podium: some View {
        VStack(alignment: .leading, spacing: TDSpacing.m) {
            Text("ranking.topPlayers")
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.textPrimary)

            HStack(alignment: .bottom, spacing: TDSpacing.s) {
                if players.count >= 3 {
                    podiumPlayer(players[1], place: 2, height: 96)
                    podiumPlayer(players[0], place: 1, height: 126)
                    podiumPlayer(players[2], place: 3, height: 78)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var leagueJourney: some View {
        VStack(alignment: .leading, spacing: TDSpacing.s) {
            Text("ranking.leagueJourney")
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TDSpacing.s) {
                    ForEach(LeagueTier.allCases) { league in
                        let isCurrent = isWeeklyLeague && liveLeaderboard?.league == league
                        HStack(spacing: TDSpacing.xs) {
                            Image(systemName: leagueSymbol(for: league))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(leagueAccent(for: league))
                            Text(leagueNameKey(league))
                                .font(TDTypography.caption)
                                .fontWeight(isCurrent ? .bold : .semibold)
                                .lineLimit(1)
                        }
                        .foregroundStyle(TDColor.textPrimary)
                        .padding(.horizontal, TDSpacing.m)
                        .padding(.vertical, TDSpacing.s)
                        .background(
                            Capsule()
                                .fill(
                                    isCurrent
                                        ? leagueAccent(for: league).opacity(0.2)
                                        : TDColor.surface
                                )
                                .overlay(
                                    Capsule().stroke(
                                        isCurrent ? leagueAccent(for: league) : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                        )
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var realDataUnavailableCard: some View {
        VStack(spacing: TDSpacing.m) {
            Image(systemName: authStore.user == nil ? "person.crop.circle.badge.questionmark" : "wifi.exclamationmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(TDColor.primary)

            VStack(spacing: TDSpacing.xs) {
                Text(unavailableTitleKey)
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(unavailableMessageKey)
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if authStore.user != nil {
                Button {
                    Task { await refreshLeaderboard() }
                } label: {
                    Label("ranking.retry", systemImage: "arrow.clockwise")
                        .font(TDTypography.secondary)
                        .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .tint(TDColor.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(TDSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: TDCornerRadius.card)
                .fill(TDColor.surface)
        )
        .tdShadow(TDShadow.card)
    }

    private func podiumPlayer(_ player: Player, place: Int, height: CGFloat) -> some View {
        VStack(spacing: TDSpacing.s) {
            ZStack(alignment: .topTrailing) {
                avatar(for: player, size: place == 1 ? 66 : 54)
                Text("\(place)")
                    .font(TDTypography.caption)
                    .fontWeight(.black)
                    .foregroundStyle(place == 1 ? TDColor.primaryDark : Color.white)
                    .frame(width: 25, height: 25)
                    .background(Circle().fill(placeColor(place)))
                    .offset(x: 4, y: -4)
            }

            Text(player.name)
                .font(TDTypography.secondary)
                .fontWeight(.bold)
                .foregroundStyle(TDColor.textPrimary)
                .lineLimit(1)

            Text("\(player.xp) XP")
                .font(TDTypography.caption)
                .foregroundStyle(TDColor.textSecondary)

            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                .fill(
                    LinearGradient(
                        colors: [placeColor(place), placeColor(place).opacity(0.62)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: height)
                .overlay(alignment: .top) {
                    Image(systemName: place == 1 ? "crown.fill" : "star.fill")
                        .foregroundStyle(place == 1 ? TDColor.primaryDark : Color.white.opacity(0.9))
                        .padding(.top, TDSpacing.m)
                }
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(hasAppeared ? 1 : 0.88, anchor: .bottom)
    }

    private var currentPositionCard: some View {
        HStack(spacing: TDSpacing.m) {
            Text("#\(currentRank)")
                .font(TDTypography.sectionTitle)
                .foregroundStyle(TDColor.primaryDark)
                .frame(width: 52, height: 52)
                .background(Circle().fill(TDColor.gold))

            VStack(alignment: .leading, spacing: TDSpacing.xs) {
                Text("ranking.yourPosition")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)
                Text(positionMessageKey)
                    .font(TDTypography.caption)
                    .foregroundStyle(positionZoneColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(currentScoreXP) XP")
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.primaryDark)
                Text(scorePeriodKey)
                    .font(TDTypography.caption)
                    .foregroundStyle(TDColor.textSecondary)
            }
        }
        .padding(TDSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: TDCornerRadius.card)
                .fill(TDColor.gold.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: TDCornerRadius.card)
                        .stroke(TDColor.gold, lineWidth: 2)
                )
        )
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: TDSpacing.m) {
            HStack {
                Text("ranking.table.title")
                    .font(TDTypography.sectionTitle)
                    .foregroundStyle(TDColor.textPrimary)
                Spacer()
                if isWeeklyLeague {
                    Label(promotionLabelKey, systemImage: "arrow.up.circle.fill")
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.success)
                } else {
                    Label("ranking.realPlayers", systemImage: "person.2.fill")
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.primary)
                }
            }

            VStack(spacing: TDSpacing.s) {
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    rankingRow(player, rank: index + 1)

                    if isWeeklyLeague, index + 1 == promotionCount {
                        HStack(spacing: TDSpacing.s) {
                            Rectangle()
                                .fill(TDColor.success.opacity(0.35))
                                .frame(height: 1)
                            Text(promotionBorderKey)
                                .font(TDTypography.caption)
                                .foregroundStyle(TDColor.success)
                                .fixedSize()
                            Rectangle()
                                .fill(TDColor.success.opacity(0.35))
                                .frame(height: 1)
                        }
                        .padding(.vertical, TDSpacing.xs)
                    }

                    if isWeeklyLeague, let demotionStart, index + 2 == demotionStart {
                        HStack(spacing: TDSpacing.s) {
                            Rectangle()
                                .fill(TDColor.error.opacity(0.35))
                                .frame(height: 1)
                            Text("ranking.demotion.border")
                                .font(TDTypography.caption)
                                .foregroundStyle(TDColor.error)
                                .fixedSize()
                            Rectangle()
                                .fill(TDColor.error.opacity(0.35))
                                .frame(height: 1)
                        }
                        .padding(.vertical, TDSpacing.xs)
                    }
                }
            }
        }
    }

    private func rankingRow(_ player: Player, rank: Int) -> some View {
        HStack(spacing: TDSpacing.m) {
            Text("\(rank)")
                .font(TDTypography.cardTitle)
                .foregroundStyle(rankColor(rank))
                .frame(width: 28)

            avatar(for: player, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(TDTypography.body)
                    .fontWeight(player.isCurrentUser ? .bold : .semibold)
                    .foregroundStyle(TDColor.textPrimary)
                if player.isCurrentUser {
                    Text("ranking.currentUser")
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.primary)
                }
            }

            Spacer()

            Text("\(player.xp) XP")
                .font(TDTypography.secondary)
                .fontWeight(.bold)
                .foregroundStyle(TDColor.textPrimary)

            if isWeeklyLeague, rank <= promotionCount {
                Image(systemName: "chevron.up.2")
                    .font(.caption.bold())
                    .foregroundStyle(TDColor.success)
            } else if isWeeklyLeague, let demotionStart, rank >= demotionStart {
                Image(systemName: "chevron.down.2")
                    .font(.caption.bold())
                    .foregroundStyle(TDColor.error)
            }
        }
        .padding(.horizontal, TDSpacing.m)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                .fill(player.isCurrentUser ? TDColor.secondarySurface : TDColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                        .stroke(player.isCurrentUser ? TDColor.primary : Color.clear, lineWidth: 2)
                )
        )
        .tdShadow(player.isCurrentUser ? TDShadow.soft : TDShadow.card)
        .accessibilityElement(children: .combine)
    }

    private func avatar(for player: Player, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(player.tint.opacity(0.18))
            Image(systemName: player.symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(player.tint)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(player.tint.opacity(0.35), lineWidth: 1))
    }

    private func placeColor(_ place: Int) -> Color {
        switch place {
        case 1: return TDColor.gold
        case 2: return Color(hex: "A9BBC5")
        default: return Color(hex: "C9875B")
        }
    }

    private var remainingTime: String {
        let calendar = Calendar.current
        let now = Date()
        let end = liveLeaderboard?.seasonEndsAt ?? calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, weekday: 2),
            matchingPolicy: .nextTime
        )
        guard let end else { return "—" }
        let components = calendar.dateComponents([.day, .hour], from: now, to: end)
        return String(localized: "ranking.timeRemaining \(max(0, components.day ?? 0)) \(max(0, components.hour ?? 0))")
    }

    private var positionMessageKey: LocalizedStringKey {
        guard isWeeklyLeague else { return "ranking.overall.position" }
        if currentRank <= promotionCount {
            return activeLeague == .obsidian
                ? "ranking.champion.active"
                : "ranking.promotion.active"
        }
        if let demotionStart, currentRank >= demotionStart {
            return activeLeague == .bronze
                ? "ranking.safe.bronze"
                : "ranking.demotion.active"
        }
        return "ranking.promotion.keepGoing"
    }

    private var seasonStatusKey: LocalizedStringKey {
        guard let liveLeaderboard else { return "ranking.realDataOnly" }
        return liveLeaderboard.scorePeriod == .weekly
            ? "ranking.liveSeason"
            : "ranking.overallRating"
    }

    private var scorePeriodKey: LocalizedStringKey {
        isWeeklyLeague ? "ranking.weeklyXP" : "ranking.totalXP"
    }

    private var heroTitleKey: LocalizedStringKey {
        liveLeaderboard == nil ? "ranking.league.overview" : "ranking.overall.title"
    }

    private var unavailableTitleKey: LocalizedStringKey {
        authStore.user == nil
            ? "ranking.realData.signIn.title"
            : "ranking.realData.unavailable.title"
    }

    private var unavailableMessageKey: LocalizedStringKey {
        authStore.user == nil
            ? "ranking.realData.signIn.message"
            : "ranking.realData.unavailable.message"
    }

    private var promotionLabelKey: LocalizedStringKey {
        activeLeague == .obsidian
            ? "ranking.champion.label"
            : "ranking.promotion.label"
    }

    private var promotionBorderKey: LocalizedStringKey {
        activeLeague == .obsidian
            ? "ranking.champion.border"
            : "ranking.promotion.border"
    }

    private var positionZoneColor: Color {
        guard isWeeklyLeague else { return TDColor.textSecondary }
        if currentRank <= promotionCount { return TDColor.success }
        if let demotionStart, currentRank >= demotionStart, activeLeague != .bronze {
            return TDColor.error
        }
        return TDColor.textSecondary
    }

    private func rankColor(_ rank: Int) -> Color {
        guard isWeeklyLeague else { return TDColor.textSecondary }
        if rank <= promotionCount { return TDColor.success }
        if let demotionStart, rank >= demotionStart, activeLeague != .bronze {
            return TDColor.error
        }
        return TDColor.textSecondary
    }

    private func leagueNameKey(_ league: LeagueTier) -> LocalizedStringKey {
        switch league {
        case .bronze: "ranking.league.bronze"
        case .silver: "ranking.league.silver"
        case .gold: "ranking.league.gold"
        case .turquoise: "ranking.league.turquoise"
        case .sapphire: "ranking.league.sapphire"
        case .ruby: "ranking.league.ruby"
        case .obsidian: "ranking.league.obsidian"
        }
    }

    private func leagueSymbol(for league: LeagueTier) -> String {
        switch league {
        case .bronze: "shield.fill"
        case .silver: "seal.fill"
        case .gold: "crown.fill"
        case .turquoise: "diamond.fill"
        case .sapphire: "sparkles"
        case .ruby: "hexagon.fill"
        case .obsidian: "mountain.2.fill"
        }
    }

    private var leagueAccent: Color {
        leagueAccent(for: activeLeague)
    }

    private func leagueAccent(for league: LeagueTier) -> Color {
        switch league {
        case .bronze: Color(hex: "D59662")
        case .silver: Color(hex: "DCE8EC")
        case .gold: TDColor.gold
        case .turquoise: Color(hex: "72E0D1")
        case .sapphire: Color(hex: "7CB7FF")
        case .ruby: Color(hex: "FF8A9A")
        case .obsidian: Color(hex: "C8B9FF")
        }
    }

    private var leagueGradient: [Color] {
        switch activeLeague {
        case .bronze: [Color(hex: "593622"), Color(hex: "9A6040"), Color(hex: "C9875B")]
        case .silver: [Color(hex: "33464F"), Color(hex: "667F8B"), Color(hex: "9DB2BC")]
        case .gold: [Color(hex: "654A10"), Color(hex: "A97B18"), Color(hex: "D9A936")]
        case .turquoise: [TDColor.tealDark, TDColor.teal, Color(hex: "36A89E")]
        case .sapphire: [Color(hex: "173E69"), Color(hex: "276AA6"), Color(hex: "4F8EF7")]
        case .ruby: [Color(hex: "5A1724"), Color(hex: "A52D47"), Color(hex: "D94F66")]
        case .obsidian: [Color(hex: "171521"), Color(hex: "312A45"), Color(hex: "51426F")]
        }
    }
}
