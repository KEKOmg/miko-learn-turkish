import XCTest

@MainActor
final class MikoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app with a fresh in-memory database so each test starts
    /// with a clean state (no completions from previous runs).
    private func launchFreshApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestReset"]
        app.launch()
        return app
    }

    func testLaunch() throws {
        let app = launchFreshApp()
        _ = app
    }

    /// Happy path: Home → start the next unfinished lesson → answer every
    /// exercise → reach the results screen. Uses real seed content; answers
    /// come from the lesson-a1-u1-l1 seed data. On a fresh launch the next
    /// unfinished lesson is the first seeded lesson.
    func testCompleteSeededLessonHappyPath() throws {
        let app = launchFreshApp()

        // Home exposes the next-lesson CTA. Query by identifier.
        let startButton = app.buttons["home.startLesson"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        tapStartLesson(app, button: startButton)

        // Immersive flow appears with its stable root and top bar counter.
        waitForLessonFlow(app)

        // 1. multipleChoice: "Что значит «Merhaba»?" → Привет
        answerMultipleChoice(app, option: "Привет")

        // 2. translateWord: "Переведите на турецкий: Привет" → merhaba
        answerTextInput(app, text: "merhaba")

        // 3. listeningComprehension: Günaydın! → Доброе утро!
        answerMultipleChoice(app, option: "Доброе утро!")

        // 4. pronunciation: mock speech always recognizes the target text.
        answerPronunciation(app)

        // 5. multipleChoice: "Что значит «Günaydın»?" → Доброе утро
        let nextPrompt = app.staticTexts["Что значит «Günaydın»?"]
        XCTAssertTrue(nextPrompt.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.scrollViews["lessonflow.exerciseScroll"].frame.contains(nextPrompt.frame),
            "A new exercise inherited the previous exercise's scroll offset"
        )
        answerMultipleChoice(app, option: "Доброе утро")

        // 6. translateWord: "До свидания (остающийся)" → güle güle (lenient)
        answerTextInput(app, text: "gule gule")

        // 7. matchPairs: greetings, matched by tap pairs from seed data.
        answerMatchPairs(app, pairs: [
            ("Привет", "Merhaba"),
            ("Привет (неформ.)", "Selam"),
            ("Доброе утро", "Günaydın"),
            ("Добрый вечер", "İyi akşamlar")
        ])

        // 8. translateWord: "До свидания" → hoşça kal (lenient).
        answerTextInput(app, text: "hosca kal")

        // Results screen.
        let resultsRoot = app.descendants(matching: .any)["lessonResults.root"]
        XCTAssertTrue(resultsRoot.waitForExistence(timeout: 10))
        let doneButton = app.buttons["lessonResults.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Урок завершён!"].exists)
        tapWhenReady(doneButton)

        // Back on the main shell — the Home CTA is available again.
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))

        // Tabs stay mounted in the shell. Profile must refresh when selected
        // after a lesson, not keep the snapshot from before completion.
        let homeXP = app.descendants(matching: .any)["home.xp"]
        XCTAssertTrue(homeXP.waitForExistence(timeout: 5))
        let earnedXP = homeXP.label.split(separator: " ").first.map(String.init) ?? ""
        XCTAssertNotEqual(earnedXP, "0")
        tapWhenReady(app.buttons["tab.profile"])
        let profileXP = app.descendants(matching: .any)["profile.stat.xp"]
        XCTAssertTrue(profileXP.waitForExistence(timeout: 5))
        XCTAssertTrue(profileXP.label.hasPrefix("\(earnedXP),"), "Profile XP did not refresh after the lesson")
        let completedLessons = app.descendants(matching: .any)["profile.stat.lessons"]
        XCTAssertTrue(completedLessons.waitForExistence(timeout: 5))
        XCTAssertTrue(completedLessons.label.hasPrefix("1,"), "Profile lesson count did not refresh")
    }

    /// Home screen shows the brand header, daily goal card, mascot
    /// greeting, and the next-lesson CTA.
    func testHomeScreenElements() throws {
        let app = launchFreshApp()

        // Header (brand name).
        XCTAssertTrue(app.staticTexts["Miko"].waitForExistence(timeout: 10))

        // VoiceOver must announce the value rather than an untranslated key.
        let xpBadge = app.descendants(matching: .any)["home.xp"]
        XCTAssertTrue(xpBadge.waitForExistence(timeout: 5))
        XCTAssertEqual(xpBadge.label, "0 XP")

        // Daily goal card title (localized RU).
        XCTAssertTrue(app.staticTexts["Дневная цель"].exists)

        // Mascot greeting (localized RU).
        XCTAssertTrue(app.staticTexts["Merhaba! Готов учить турецкий?"].exists)

        // CTA.
        let startButton = app.buttons["home.startLesson"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertEqual(startButton.label, "НАЧАТЬ УРОК")
        let scroll = app.scrollViews["home.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(scroll.frame.contains(startButton.frame), "Home CTA is clipped on first load")
        let nextTitle = app.staticTexts["home.nextLesson.title"]
        XCTAssertTrue(nextTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(scroll.frame.contains(nextTitle.frame), "Next-lesson title is hidden under the tab bar")
    }

    /// Course Map → tap an unlocked lesson → LessonFlow appears. On a fresh
    /// launch only the first seeded lesson is unlocked.
    func testCourseMapUnlockedLessonLaunchesFlow() throws {
        let app = launchFreshApp()

        // Switch to the Course Map tab.
        let mapTab = app.buttons["tab.courseMap"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 10))
        tapWhenReady(mapTab)

        // Course map root appears.
        let courseMapRoot = app.descendants(matching: .any)["courseMap.root"]
        XCTAssertTrue(courseMapRoot.waitForExistence(timeout: 10))
        let a1Picker = app.buttons["courseMap.levelPicker.a1"]
        XCTAssertTrue(a1Picker.waitForExistence(timeout: 10), "Course Map content did not finish loading")
        if !a1Picker.isSelected {
            tapWhenReady(a1Picker)
        }

        // The first seeded lesson node is unlocked and tappable.
        let firstLessonNode = app.buttons["courseMap.lesson.a1.u1.l1"]
        if !firstLessonNode.waitForExistence(timeout: 10) {
            XCTContext.runActivity(named: "First lesson missing from fresh Course Map") { activity in
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.lifetime = .keepAlways
                activity.add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.lifetime = .keepAlways
                activity.add(screenshot)
            }
        }
        XCTAssertTrue(firstLessonNode.exists, "Fresh A1 map did not expose the first lesson")
        tapWhenReady(firstLessonNode)

        // Lesson flow appears.
        let lessonFlowRoot = waitForLessonFlow(app)

        // Close the lesson via the X button + quit confirmation.
        let closeButton = app.buttons["lessonflow.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        tapWhenReady(closeButton)

        // Quit confirmation alert → confirm.
        let quitButton = app.buttons["Выйти"]
        XCTAssertTrue(quitButton.waitForExistence(timeout: 5))
        tapWhenReady(quitButton)

        // Back on the course map after the cover is actually dismissed.
        XCTAssertTrue(lessonFlowRoot.waitForNonExistence(timeout: 10))
        XCTAssertTrue(courseMapRoot.waitForExistence(timeout: 10))
    }

    /// A2 is directly reachable from the level picker and reuses the same
    /// unit/lesson path UI as A1. On a fresh profile its lessons are visible
    /// but locked until A1 has been completed.
    func testCourseMapDisplaysA2FromLevelPicker() throws {
        let app = launchFreshApp()

        let mapTab = app.buttons["tab.courseMap"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 10))
        tapWhenReady(mapTab)

        let a2Picker = app.buttons["courseMap.levelPicker.a2"]
        XCTAssertTrue(a2Picker.waitForExistence(timeout: 10))
        XCTAssertFalse(a2Picker.label.contains("level."), "A2 level title is an untranslated key")
        XCTAssertFalse(app.buttons["courseMap.levelPicker.a1"].label.contains("level."),
                       "A1 level title is an untranslated key")
        tapWhenReady(a2Picker)

        let a2Level = app.descendants(matching: .any)["courseMap.level.a2"]
        if !a2Level.waitForExistence(timeout: 3), a2Picker.exists, a2Picker.isEnabled {
            // XCTest can deliver a tap to the animated picker before the
            // scroll view has finished settling. Confirm the selected panel,
            // then retry only this harmless level-selection action.
            tapWhenReady(a2Picker)
        }
        XCTAssertTrue(a2Level.waitForExistence(timeout: 10))
        XCTAssertTrue(a2Level.label.contains("A2"))

        let firstA2Lesson = app.buttons["courseMap.lesson.a2.u1.l1"]
        XCTAssertTrue(firstA2Lesson.waitForExistence(timeout: 5))
        XCTAssertFalse(firstA2Lesson.isEnabled)
    }

    /// Complete the first seeded lesson through the UI. Used as a setup step
    /// for practice-mode tests.
    private func completeFirstLesson(_ app: XCUIApplication) {
        let startButton = app.buttons["home.startLesson"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        tapStartLesson(app, button: startButton)

        waitForLessonFlow(app)

        answerMultipleChoice(app, option: "Привет")
        answerTextInput(app, text: "merhaba")
        answerMultipleChoice(app, option: "Доброе утро!")

        answerPronunciation(app)

        answerMultipleChoice(app, option: "Доброе утро")
        answerTextInput(app, text: "gule gule")
        answerMatchPairs(app, pairs: [
            ("Привет", "Merhaba"),
            ("Привет (неформ.)", "Selam"),
            ("Доброе утро", "Günaydın"),
            ("Добрый вечер", "İyi akşamlar")
        ])
        answerTextInput(app, text: "hosca kal")

        let resultsRoot = app.descendants(matching: .any)["lessonResults.root"]
        XCTAssertTrue(resultsRoot.waitForExistence(timeout: 10))
        let doneButton = app.buttons["lessonResults.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        tapWhenReady(doneButton)
    }

    /// Practice mode: after completing a lesson, tapping it again from the
    /// Course Map should launch the lesson flow in practice mode and show
    /// the "Повторение завершено!" results label.
    func testCompletedLessonLaunchesPracticeMode() throws {
        let app = launchFreshApp()

        // 1. Complete the first seeded lesson.
        completeFirstLesson(app)

        // 2. Switch to the Course Map.
        let mapTab = app.buttons["tab.courseMap"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 10))
        tapWhenReady(mapTab)

        let courseMapRoot = app.descendants(matching: .any)["courseMap.root"]
        XCTAssertTrue(courseMapRoot.waitForExistence(timeout: 10))

        // 3. The first lesson is now completed — tap it to start practice.
        let firstLessonNode = app.buttons["courseMap.lesson.a1.u1.l1"]
        XCTAssertTrue(firstLessonNode.waitForExistence(timeout: 10))
        tapWhenReady(firstLessonNode)

        // 4. Lesson flow opens (practice mode, but the counter is the same).
        waitForLessonFlow(app)

        // 5. Complete all exercises again (practice replay).
        answerMultipleChoice(app, option: "Привет")
        answerTextInput(app, text: "merhaba")
        answerMultipleChoice(app, option: "Доброе утро!")

        answerPronunciation(app)

        answerMultipleChoice(app, option: "Доброе утро")
        answerTextInput(app, text: "gule gule")
        answerMatchPairs(app, pairs: [
            ("Привет", "Merhaba"),
            ("Привет (неформ.)", "Selam"),
            ("Доброе утро", "Günaydın"),
            ("Добрый вечер", "İyi akşamlar")
        ])
        answerTextInput(app, text: "hosca kal")

        // 6. Results screen shows the practice-specific label.
        let resultsRoot = app.descendants(matching: .any)["lessonResults.root"]
        XCTAssertTrue(resultsRoot.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Повторение завершено!"].exists)

        let doneButton = app.buttons["lessonResults.done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        tapWhenReady(doneButton)
    }

    /// Full seeded-course smoke: follows the same next-lesson path a learner
    /// uses and answers every exercise from A1.1 through A2.14. The plan is
    /// decoded from the checked-in seed JSON so this test cannot silently
    /// drift when lesson order or exercise content changes.
    func testCompleteEntireSeedCourse() throws {
        let app = launchFreshApp()
        let plan = try FullCourseQAPlan.load()

        XCTAssertEqual(plan.lessons.count, 28)
        XCTAssertEqual(plan.lessons.flatMap(\.exercises).count, 217)

        for (lessonIndex, lesson) in plan.lessons.enumerated() {
            XCTContext.runActivity(named: "\(lessonIndex + 1)/\(plan.lessons.count) \(lesson.key)") { _ in
                let startButton = app.buttons["home.startLesson"]
                XCTAssertTrue(startButton.waitForExistence(timeout: 10))
                tapStartLesson(app, button: startButton)
                waitForLessonFlow(app)

                let counter = app.staticTexts["lessonflow.counter"]
                XCTAssertEqual(counter.value as? String, "1 из \(lesson.exercises.count)")

                for exercise in lesson.exercises {
                    answerCorrectly(app, exercise: exercise, vocabulary: plan.vocabulary)
                }

                let resultsRoot = app.descendants(matching: .any)["lessonResults.root"]
                XCTAssertTrue(resultsRoot.waitForExistence(timeout: 10), "No results for \(lesson.key)")
                let doneButton = app.buttons["lessonResults.done"]
                XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
                tapWhenReady(doneButton)
            }
        }

        let reviewButton = app.buttons["home.reviewCourse"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["home.startLesson"].exists)
        XCTAssertTrue(app.staticTexts["Ты прошёл все уроки! Повторить любой урок можно на карте курса."].exists)
        tapWhenReady(reviewButton)
        XCTAssertTrue(app.descendants(matching: .any)["courseMap.root"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    /// Shop screen shows gems, hearts, and a refill action. On a fresh launch
    /// the user has 0 gems and 5/5 hearts, so the refill button is disabled
    /// with a "hearts full" message — a deterministic state that does not
    /// require modifying seed data.
    func testShopScreenElements() throws {
        let app = launchFreshApp()

        let shopTab = app.buttons["tab.shop"]
        XCTAssertTrue(shopTab.waitForExistence(timeout: 10))
        tapWhenReady(shopTab)

        let shopRoot = app.descendants(matching: .any)["shop.root"]
        XCTAssertTrue(shopRoot.waitForExistence(timeout: 10))

        // Balance section with gems and hearts.
        let gems = app.descendants(matching: .any)["shop.gems"]
        XCTAssertTrue(gems.waitForExistence(timeout: 5))
        XCTAssertEqual(gems.value as? String, "0")
        let hearts = app.descendants(matching: .any)["shop.hearts"]
        XCTAssertTrue(hearts.waitForExistence(timeout: 5))
        XCTAssertEqual(hearts.value as? String, "5/5")

        // Refill button is present (disabled because hearts are full on
        // a fresh launch).
        let refillButton = app.buttons["shop.refill.button"]
        XCTAssertTrue(refillButton.waitForExistence(timeout: 5))
        XCTAssertTrue(refillButton.isEnabled == false)
    }

    // MARK: - Helpers

    private func answerMultipleChoice(_ app: XCUIApplication, option: String) {
        let optionButton = app.buttons[option]
        XCTAssertTrue(optionButton.waitForExistence(timeout: 5), "Missing option: \(option)")
        scrollExerciseToReveal(app, element: optionButton)
        tapWhenReady(optionButton)

        let checkButton = app.buttons["exercise.check"]
        if !waitForEnabled(checkButton, timeout: 3) {
            let refreshedOption = app.buttons[option]
            scrollExerciseToReveal(app, element: refreshedOption)
            XCTAssertTrue(refreshedOption.waitForExistence(timeout: 5))
            refreshedOption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if !waitForEnabled(checkButton, timeout: 5) {
            XCTContext.runActivity(named: "Option selection failure: \(option)") { activity in
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.lifetime = .keepAlways
                activity.add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.lifetime = .keepAlways
                activity.add(screenshot)
            }
        }
        XCTAssertTrue(waitForEnabled(checkButton, timeout: 5),
                      "Selecting option did not enable Check: \(option)")
        tapCheck(app)
        tapContinue(app)
    }

    private func answerPronunciation(_ app: XCUIApplication) {
        let micButton = app.buttons["exercise.pronunciation.record"]
        XCTAssertTrue(micButton.waitForExistence(timeout: 5))
        scrollExerciseToReveal(app, element: micButton)
        tapWhenReady(micButton)

        let continueButton = app.buttons["exercise.continue"]
        if !continueButton.waitForExistence(timeout: 3) {
            tapWhenReady(app.buttons["exercise.pronunciation.record"])
        }
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5),
                      "Pronunciation action did not produce Continue")
        tapContinue(app)
    }

    private func answerTextInput(_ app: XCUIApplication, text: String) {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        scrollExerciseToReveal(app, element: field)
        field.tap()
        field.typeText(text)
        // Multiline sentence fields insert a newline instead of submitting.
        // Use the same explicit Check action in both text exercise types.
        tapCheck(app)
        tapContinue(app)
    }

    private func answerMatchPairs(_ app: XCUIApplication, pairs: [(String, String)]) {
        for (source, target) in pairs {
            let sourceButton = app.buttons[source]
            XCTAssertTrue(sourceButton.waitForExistence(timeout: 5), "Missing pair source: \(source)")
            scrollExerciseToReveal(app, element: sourceButton)
            tapWhenReady(sourceButton)
            let targetButton = app.buttons[target]
            XCTAssertTrue(targetButton.waitForExistence(timeout: 5), "Missing pair target: \(target)")
            scrollExerciseToReveal(app, element: targetButton)
            tapWhenReady(targetButton)

            // A correct match animates both cards out of the unmatched board.
            // Wait for that transition before resolving the next pair so a
            // reordered card cannot receive a stale-coordinate tap.
            if !sourceButton.waitForNonExistence(timeout: 3) {
                // XCTest occasionally drops one synthesized event even though
                // the card is visible. Replay only the side whose selected
                // accessibility state proves that its first tap was missed.
                if sourceButton.value as? String == "selected" {
                    tapWhenReady(targetButton)
                } else if targetButton.value as? String == "selected" {
                    tapWhenReady(sourceButton)
                } else {
                    tapWhenReady(sourceButton)
                    tapWhenReady(targetButton)
                }
            }
            XCTAssertTrue(sourceButton.waitForNonExistence(timeout: 5),
                          "Matched pair source remained interactive: \(source)")
            XCTAssertTrue(
                targetButton.waitForNonExistence(timeout: 5),
                "Matched pair target remained interactive: \(target)"
            )
        }
        tapContinue(app)
    }

    private func answerCorrectly(
        _ app: XCUIApplication,
        exercise: FullCourseQAPlan.Exercise,
        vocabulary: [String: FullCourseQAPlan.Vocabulary]
    ) {
        switch exercise.type {
        case "multipleChoice", "listeningComprehension":
            answerMultipleChoice(app, option: exercise.correctOption)
        case "translateWord", "translateSentence":
            answerTextInput(app, text: exercise.correctAnswerText)
        case "fillBlank":
            answerMultipleChoice(app, option: exercise.blank)
        case "buildSentence":
            answerBuildSentence(app, words: exercise.sentenceWords)
        case "matchPairs":
            answerMatchPairs(app, pairs: exercise.pairs)
        case "pronunciation":
            answerPronunciation(app)
        case "vocabularyReview":
            let items = exercise.vocabularyKeys.compactMap { vocabulary[$0] }
            answerVocabularyReview(app, items: items)
        default:
            XCTFail("Unsupported seeded exercise type: \(exercise.type)")
        }
    }

    private func answerBuildSentence(_ app: XCUIApplication, words: [String]) {
        for word in words {
            let matchingWords = app.buttons.matching(NSPredicate(format: "label == %@", word))
            let bankWord = matchingWords.element(boundBy: max(0, matchingWords.count - 1))
            XCTAssertTrue(bankWord.waitForExistence(timeout: 5), "Missing word-bank token: \(word)")
            scrollExerciseToReveal(app, element: bankWord)
            tapWhenReady(bankWord)
        }
        tapCheck(app)
        tapContinue(app)
    }

    private func answerVocabularyReview(
        _ app: XCUIApplication,
        items: [FullCourseQAPlan.Vocabulary]
    ) {
        XCTAssertFalse(items.isEmpty, "Vocabulary review has no referenced items")

        for questionIndex in items.indices {
            guard let current = items.first(where: { app.staticTexts[$0.targetText].exists }) else {
                XCTFail("Could not identify current vocabulary-review question")
                return
            }

            let answer = app.buttons[current.sourceText]
            XCTAssertTrue(answer.waitForExistence(timeout: 5), "Missing review answer: \(current.sourceText)")
            scrollExerciseToReveal(app, element: answer)
            tapWhenReady(answer)
            tapCheck(app)

            let continueButton = app.buttons["exercise.continue"]
            XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
            scrollExerciseToReveal(app, element: continueButton)
            tapWhenReady(continueButton)

            if questionIndex < items.count - 1 {
                XCTAssertTrue(
                    currentTargetDisappeared(app, target: current.targetText, timeout: 5),
                    "Vocabulary review did not advance"
                )
            } else {
                waitForLessonAdvanceOrResults(app)
            }
        }
    }

    private func currentTargetDisappeared(
        _ app: XCUIApplication,
        target: String,
        timeout: TimeInterval
    ) -> Bool {
        app.staticTexts[target].waitForNonExistence(timeout: timeout)
    }

    private func waitForLessonAdvanceOrResults(_ app: XCUIApplication) {
        let continueButton = app.buttons["exercise.continue"]
        let resultsRoot = app.descendants(matching: .any)["lessonResults.root"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                resultsRoot.exists || !continueButton.exists
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed)
    }

    private func tapContinue(_ app: XCUIApplication) {
        let continueButton = app.buttons["exercise.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Continue button not shown")
        scrollExerciseToReveal(app, element: continueButton)

        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.exists && element.isEnabled
            },
            object: continueButton
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [ready], timeout: 10),
            .completed,
            "Continue button did not become enabled"
        )

        let counter = app.staticTexts["lessonflow.counter"]
        let previousCounterValue = counter.value as? String
        tapElement(continueButton)

        let resultsRoot = app.descendants(matching: .any)["lessonResults.root"]
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                resultsRoot.exists || (counter.exists && counter.value as? String != previousCounterValue)
            },
            object: nil
        )
        var advanceResult = XCTWaiter().wait(for: [advanced], timeout: 10)
        if advanceResult != .completed, continueButton.exists, continueButton.isEnabled {
            // XCTest can synthesize an element tap while a ScrollView still
            // owns the gesture. A second, center-coordinate tap is bounded
            // by the unchanged exercise counter to avoid double submission.
            continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let retry = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    resultsRoot.exists || (counter.exists && counter.value as? String != previousCounterValue)
                },
                object: nil
            )
            advanceResult = XCTWaiter().wait(for: [retry], timeout: 10)
        }
        if advanceResult != .completed {
            XCTContext.runActivity(named: "Lesson transition failure") { activity in
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.lifetime = .keepAlways
                activity.add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.lifetime = .keepAlways
                activity.add(screenshot)
            }
        }
        XCTAssertEqual(
            advanceResult,
            .completed,
            "Lesson did not advance after Continue"
        )
    }

    private func tapCheck(_ app: XCUIApplication) {
        let checkButton = app.buttons["exercise.check"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5), "Check button not shown")
        scrollExerciseToReveal(app, element: checkButton)

        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.exists && element.isEnabled
            },
            object: checkButton
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [ready], timeout: 10),
            .completed,
            "Check button did not become enabled"
        )
        tapElement(checkButton)

        let continueButton = app.buttons["exercise.continue"]
        if !continueButton.waitForExistence(timeout: 3), checkButton.exists, checkButton.isEnabled {
            // A ScrollView can report a button hittable while a synthesized
            // element tap is swallowed by its gesture recognizer. Retry at
            // the visible button center once the first gesture has settled.
            checkButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if !continueButton.waitForExistence(timeout: 3), checkButton.exists, checkButton.isEnabled {
            scrollExerciseToReveal(app, element: checkButton)
            checkButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if !continueButton.waitForExistence(timeout: 5) {
            XCTContext.runActivity(named: "Check transition failure") { activity in
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.lifetime = .keepAlways
                activity.add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.lifetime = .keepAlways
                activity.add(screenshot)
            }
        }
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5),
                      "Check action did not produce Continue")
    }

    private func scrollExerciseToReveal(_ app: XCUIApplication, element: XCUIElement) {
        let scroll = app.scrollViews["lessonflow.exerciseScroll"]
        guard scroll.waitForExistence(timeout: 2) else { return }

        var viewport = scroll.frame
        viewport.size.height = max(0, viewport.height - TDTestLayout.bottomActionBuffer)
        for _ in 0..<4 where !viewport.contains(element.frame) {
            scroll.swipeUp()
        }
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.exists && element.isEnabled
            },
            object: element
        )
        return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
    }

    private func tapWhenReady(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        message: String = "Element did not become tappable"
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)

        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.exists && element.isEnabled
            },
            object: element
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [ready], timeout: timeout),
            .completed,
            message
        )
        tapElement(element)
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func tapStartLesson(_ app: XCUIApplication, button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Start lesson button not shown")
        let scroll = app.scrollViews["home.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        // A partially clipped button can report isHittable while its center
        // is below the scroll viewport, alongside the custom tab bar.
        for _ in 0..<3 {
            if scroll.frame.insetBy(dx: 0, dy: 8).contains(button.frame) { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(scroll.frame.contains(button.frame), "Start lesson button remains clipped")
        tapWhenReady(button, timeout: 5, message: "Start lesson button is not actionable")

        let lessonRoot = app.descendants(matching: .any)["lessonflow.root"]
        if !lessonRoot.waitForExistence(timeout: 3), button.exists, button.isEnabled {
            tapWhenReady(button, timeout: 5, message: "Start lesson retry is not actionable")
        }
    }

    @discardableResult
    private func waitForLessonFlow(_ app: XCUIApplication) -> XCUIElement {
        let root = app.descendants(matching: .any)["lessonflow.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 10), "Lesson flow root not shown")
        XCTAssertTrue(
            app.staticTexts["lessonflow.counter"].waitForExistence(timeout: 10),
            "Lesson flow did not finish loading"
        )
        return root
    }
}

private enum TDTestLayout {
    static let bottomActionBuffer: CGFloat = 48
}

private struct FullCourseQAPlan {
    struct Lesson {
        let key: String
        let exercises: [Exercise]
    }

    struct Exercise {
        let type: String
        let correctAnswerText: String
        let correctOption: String
        let blank: String
        let sentenceWords: [String]
        let pairs: [(String, String)]
        let vocabularyKeys: [String]
    }

    struct Vocabulary {
        let sourceText: String
        let targetText: String
    }

    let lessons: [Lesson]
    let vocabulary: [String: Vocabulary]

    static func load(filePath: StaticString = #filePath) throws -> FullCourseQAPlan {
        let testsDirectory = URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent()
        let seedDirectory = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Miko/Data/SeedData", isDirectory: true)

        let vocabularyJSON = try object(at: seedDirectory.appendingPathComponent("vocabulary.json"))
        guard let vocabularyRows = vocabularyJSON as? [[String: Any]] else {
            throw QAPlanError.invalidJSON("vocabulary.json")
        }
        let vocabulary = Dictionary(uniqueKeysWithValues: try vocabularyRows.map { row in
            guard let key = row["key"] as? String,
                  let source = row["sourceText"] as? String,
                  let target = row["targetText"] as? String else {
                throw QAPlanError.invalidJSON("vocabulary row")
            }
            return (key, Vocabulary(sourceText: source, targetText: target))
        })

        var lessons: [Lesson] = []
        for levelKey in ["a1", "a2"] {
            let level = try dictionary(at: seedDirectory.appendingPathComponent("level-\(levelKey).json"))
            guard let unitKeys = level["unitKeys"] as? [String] else {
                throw QAPlanError.invalidJSON("level-\(levelKey).json")
            }

            for unitKey in unitKeys {
                let unitFile = "unit-\(unitKey.replacingOccurrences(of: ".", with: "-")).json"
                let unit = try dictionary(at: seedDirectory.appendingPathComponent(unitFile))
                guard let lessonKeys = unit["lessonKeys"] as? [String] else {
                    throw QAPlanError.invalidJSON(unitFile)
                }

                for lessonKey in lessonKeys {
                    let lessonFile = "lesson-\(lessonKey.replacingOccurrences(of: ".", with: "-")).json"
                    let lessonJSON = try dictionary(at: seedDirectory.appendingPathComponent(lessonFile))
                    guard let rows = lessonJSON["exercises"] as? [[String: Any]] else {
                        throw QAPlanError.invalidJSON(lessonFile)
                    }
                    let exercises = try rows
                        .sorted { ($0["orderIndex"] as? Int ?? 0) < ($1["orderIndex"] as? Int ?? 0) }
                        .map(parseExercise)
                    lessons.append(Lesson(key: lessonKey, exercises: exercises))
                }
            }
        }

        return FullCourseQAPlan(lessons: lessons, vocabulary: vocabulary)
    }

    private static func parseExercise(_ row: [String: Any]) throws -> Exercise {
        guard let type = row["type"] as? String else {
            throw QAPlanError.invalidJSON("exercise type")
        }
        let answer = row["correctAnswerText"] as? String ?? ""
        let payload = row["payload"] as? [String: Any] ?? [:]
        let options = payload["options"] as? [String] ?? []
        let correctIndex = payload["correctIndex"] as? Int
        let correctOption = correctIndex.flatMap { options.indices.contains($0) ? options[$0] : nil } ?? ""
        let pairRows = payload["pairs"] as? [[String: Any]] ?? []
        let pairs = try pairRows.map { pair -> (String, String) in
            guard let source = pair["source"] as? String,
                  let target = pair["target"] as? String else {
                throw QAPlanError.invalidJSON("match pair")
            }
            return (source, target)
        }

        return Exercise(
            type: type,
            correctAnswerText: answer,
            correctOption: correctOption,
            blank: payload["blank"] as? String ?? "",
            sentenceWords: payload["sentenceWords"] as? [String] ?? [],
            pairs: pairs,
            vocabularyKeys: row["vocabularyKeys"] as? [String] ?? []
        )
    }

    private static func dictionary(at url: URL) throws -> [String: Any] {
        guard let result = try object(at: url) as? [String: Any] else {
            throw QAPlanError.invalidJSON(url.lastPathComponent)
        }
        return result
    }

    private static func object(at url: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private enum QAPlanError: Error {
        case invalidJSON(String)
    }
}
