import SwiftUI
import SwiftData

/// Course Map screen.
///
/// Renders the full Course → Level → Unit → Lesson hierarchy from SwiftData
/// as a vertical learning path on a cream background. Each lesson is a
/// rounded node with completed / unlocked / locked visual states. Tapping an
/// unlocked (or completed) lesson launches the shared lesson flow via
/// `appState.activeLessonID`; locked lessons do nothing.
///
/// No course structure is hardcoded here — the view renders whatever the
/// view model's `CourseMapSnapshot` contains.
struct CourseMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appContainer) private var appContainer

    @State private var viewModel: CourseMapViewModel?
    @State private var selectedLevelKey: String?

    var body: some View {
        ScrollView {
            VStack(spacing: TDSpacing.xl) {
                header

                if let viewModel, let snapshot = viewModel.snapshot {
                    levelPicker(snapshot)
                    pathContent(viewModel: viewModel, snapshot: snapshot)
                } else {
                    loadingView
                }
            }
            .padding(.horizontal, TDSpacing.l)
            .padding(.top, TDSpacing.l)
            .padding(.bottom, TDSpacing.xxl)
        }
        .background(TDColor.background)
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("courseMap.root")
                .allowsHitTesting(false)
        }
        .task {
            if viewModel == nil {
                let vm = CourseMapViewModel(
                    repository: appContainer?.lessonProgressRepository
                        ?? LessonProgressRepository(
                            context: modelContext,
                            profileID: appState.activeProfileID
                        ),
                    heartsRepository: appContainer?.heartsRepository,
                    gamificationRepository: appContainer?.gamificationRepository
                )
                viewModel = vm
                vm.load()
                synchronizeSelectedLevel(with: vm.snapshot)
            } else {
                viewModel?.load()
                synchronizeSelectedLevel(with: viewModel?.snapshot)
            }
        }
        .onChange(of: appState.activeLessonID) { _, newValue in
            if newValue == nil {
                viewModel?.load()
                synchronizeSelectedLevel(with: viewModel?.snapshot)
            }
        }
        .onChange(of: appState.restoredProgressRevision) { _, _ in
            viewModel?.load()
            synchronizeSelectedLevel(with: viewModel?.snapshot)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TDSpacing.xs) {
            Text("screen.courseMap.title")
                .font(TDTypography.largeTitle)
                .foregroundStyle(TDColor.screenTitle)
            Text("screen.courseMap.subtitle")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("courseMap.header")
    }

    // MARK: - Path

    @ViewBuilder
    private func levelPicker(_ snapshot: CourseMapSnapshot) -> some View {
        if snapshot.levels.count > 1 {
            HStack(spacing: TDSpacing.s) {
                ForEach(snapshot.levels) { level in
                    levelPickerButton(level)
                }
            }
            .padding(TDSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .fill(TDColor.secondarySurface)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("courseMap.levelPicker")
        }
    }

    private func levelPickerButton(_ level: LevelSection) -> some View {
        let isSelected = selectedLevelKey == level.key

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedLevelKey = level.key
            }
        } label: {
            HStack(spacing: TDSpacing.s) {
                Image(systemName: levelPickerIcon(for: level))
                    .font(.system(size: 14, weight: .bold))
                Text(localizedLevelTitle(level.cefrRaw))
                    .font(TDTypography.secondary)
                    .fontWeight(.bold)
            }
            .foregroundStyle(isSelected ? TDColor.textOnPrimary : TDColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TDSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.small)
                    .fill(isSelected ? TDColor.primary : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("courseMap.levelPicker.\(level.key)")
    }

    private func levelPickerIcon(for level: LevelSection) -> String {
        if level.isCompleted { return "checkmark.circle.fill" }
        if level.isAvailable { return "play.circle.fill" }
        return "lock.fill"
    }

    @ViewBuilder
    private func pathContent(viewModel: CourseMapViewModel, snapshot: CourseMapSnapshot) -> some View {
        if !viewModel.canPlay {
            heartsDepletedBanner
        }
        ForEach(visibleLevels(in: snapshot)) { level in
            levelSection(level, in: snapshot)
        }
    }

    private var heartsDepletedBanner: some View {
        HStack(spacing: TDSpacing.s) {
            MascotView(mood: .sad, size: 68)
            Text("courseMap.hearts.depleted")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textPrimary)
            Spacer()
        }
        .padding(.horizontal, TDSpacing.m)
        .padding(.vertical, TDSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                .fill(TDColor.secondarySurface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("courseMap.hearts.depleted")
    }

    @ViewBuilder
    private func levelSection(_ level: LevelSection, in snapshot: CourseMapSnapshot) -> some View {
        VStack(spacing: TDSpacing.l) {
            // Level banner
            HStack {
                Image(systemName: "rosette")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(localizedLevelTitle(level.cefrRaw))
                    .font(TDTypography.sectionTitle)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, TDSpacing.l)
            .padding(.vertical, TDSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.card)
                    .fill(TDColor.primaryDark)
            )
            .tdShadow(TDShadow.soft)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("courseMap.level.\(level.key)")

            ForEach(level.units) { unit in
                unitSection(unit)
            }

            if let nextLevel = nextLevel(after: level, in: snapshot) {
                nextLevelTransition(from: level, to: nextLevel)
            }
        }
    }

    private func nextLevelTransition(from level: LevelSection, to nextLevel: LevelSection) -> some View {
        let canAdvance = level.isCompleted

        return Button {
            guard canAdvance else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedLevelKey = nextLevel.key
            }
        } label: {
            HStack(spacing: TDSpacing.m) {
                VStack(alignment: .leading, spacing: TDSpacing.xs) {
                    if canAdvance {
                        Text("courseMap.nextLevel.continue")
                    } else {
                        Text("courseMap.nextLevel.locked")
                    }
                    Text(localizedLevelTitle(nextLevel.cefrRaw))
                        .font(TDTypography.cardTitle)
                        .fontWeight(.bold)
                }
                .font(TDTypography.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: canAdvance ? "arrow.right.circle.fill" : "lock.circle.fill")
                    .font(.system(size: 34, weight: .bold))
            }
            .foregroundStyle(canAdvance ? TDColor.textOnPrimary : TDColor.textSecondary)
            .padding(TDSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.card)
                    .fill(canAdvance ? TDColor.primary : TDColor.secondarySurface)
            )
            .tdShadow(TDShadow.soft)
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance)
        .accessibilityIdentifier("courseMap.nextLevel.\(nextLevel.key)")
    }

    @ViewBuilder
    private func unitSection(_ unit: UnitSection) -> some View {
        VStack(spacing: TDSpacing.m) {
            // Unit header
            VStack(alignment: .leading, spacing: TDSpacing.xs) {
                Text(localizedUnitTitle(unit))
                    .font(TDTypography.cardTitle)
                    .foregroundStyle(TDColor.textPrimary)
                Text(localizedUnitSummary(unit))
                    .font(TDTypography.secondary)
                    .foregroundStyle(TDColor.textSecondary)
                if unit.lessons.count > 0 {
                    Text(String(localized: "courseMap.unit.progress \(unit.completedCount) \(unit.lessons.count)"))
                        .font(TDTypography.caption)
                        .foregroundStyle(TDColor.primary)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TDSpacing.m)
            .padding(.vertical, TDSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: TDCornerRadius.smallCard)
                    .fill(TDColor.secondarySurface)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("courseMap.unit.\(unit.key)")

            // Vertical lesson path with zig-zag offsets and connectors.
            ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, node in
                VStack(spacing: 0) {
                    if index > 0 {
                        LessonConnector(direction: index % 2 == 0 ? .left : .right)
                    }
                    HStack {
                        if index % 2 == 1 { Spacer(minLength: 0) }
                        LessonNodeView(
                            node: node,
                            position: index,
                            onTap: {
                                if let viewModel {
                                    launch(node, using: viewModel)
                                }
                            }
                        )
                        .frame(width: 200)
                        if index % 2 == 0 { Spacer(minLength: 0) }
                    }
                    .padding(.vertical, TDSpacing.xs)
                }
            }
        }
    }

    // MARK: - Helpers

    private func visibleLevels(in snapshot: CourseMapSnapshot) -> [LevelSection] {
        guard let selectedLevelKey,
              let selected = snapshot.levels.first(where: { $0.key == selectedLevelKey }) else {
            return snapshot.levels.first.map { [$0] } ?? []
        }
        return [selected]
    }

    private func nextLevel(after level: LevelSection, in snapshot: CourseMapSnapshot) -> LevelSection? {
        guard let index = snapshot.levels.firstIndex(where: { $0.id == level.id }),
              snapshot.levels.indices.contains(index + 1) else { return nil }
        return snapshot.levels[index + 1]
    }

    private func synchronizeSelectedLevel(with snapshot: CourseMapSnapshot?) {
        guard let snapshot, !snapshot.levels.isEmpty else {
            selectedLevelKey = nil
            return
        }

        guard let selectedLevelKey,
              let selected = snapshot.levels.first(where: { $0.key == selectedLevelKey }) else {
            self.selectedLevelKey = snapshot.suggestedLevelKey ?? snapshot.levels[0].key
            return
        }

        // Move forward as soon as the selected level is finished. A learner
        // can still use the picker to return to A1 for practice afterwards.
        if selected.isCompleted,
           let suggested = snapshot.suggestedLevelKey,
           suggested != selectedLevelKey {
            self.selectedLevelKey = suggested
        }
    }

    /// Forwards a playable selection to the shared launcher in the same
    /// button action. Keeping this synchronous avoids losing a transient
    /// view-model request between SwiftUI observation passes.
    private func launch(_ node: LessonNode, using viewModel: CourseMapViewModel) {
        viewModel.select(node)
        guard let lessonID = viewModel.requestedLessonID else { return }
        appState.activeLessonMode = viewModel.requestedMode
        appState.activeLessonID = lessonID
        viewModel.consumeRequest()
    }

    private func localizedLevelTitle(_ cefrRaw: String) -> String {
        let key = "level.\(cefrRaw.lowercased())"
        return NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "CEFR level title")
    }

    private func localizedUnitTitle(_ unit: UnitSection) -> String {
        localizedContentValue(
            storedKey: unit.titleKey,
            fallbackKey: "unit.\(unit.key).title"
        )
    }

    private func localizedUnitSummary(_ unit: UnitSection) -> String {
        localizedContentValue(
            storedKey: unit.summaryKey,
            fallbackKey: "unit.\(unit.key).summary"
        )
    }

    private func localizedContentValue(storedKey: String, fallbackKey: String) -> String {
        let trimmedKey = storedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryKey = trimmedKey.isEmpty ? fallbackKey : trimmedKey
        let primaryValue = String(localized: String.LocalizationValue(primaryKey))
        if !primaryValue.isEmpty, primaryValue != primaryKey {
            return primaryValue
        }

        return String(localized: String.LocalizationValue(fallbackKey))
    }

    private var loadingView: some View {
        VStack(spacing: TDSpacing.m) {
            ProgressView()
                .tint(TDColor.primary)
                .controlSize(.large)
            Text("courseMap.loading")
                .font(TDTypography.secondary)
                .foregroundStyle(TDColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}
