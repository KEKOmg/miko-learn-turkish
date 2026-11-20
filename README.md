# Miko Learn Turkish

Miko is a native iOS app for Russian-speaking learners of Turkish. A course map guides learners from A1 to A2 through short lessons, and completed lessons can be replayed in practice mode.

## Inside the app

- **28 lessons and 217 exercises** across A1 and A2. Exercises include translation, sentence building, matching, listening and pronunciation.
- **Local guest mode.** The course ships with the app, and SwiftData stores learning progress on the device.
- **Progress and motivation.** Lesson results, XP, streaks, daily goals, hearts and weekly leagues give learners feedback as they advance.
- **Turkish audio and answer checking.** System text-to-speech plays Turkish prompts. Apple Speech supports pronunciation exercises on supported devices. Typed answers distinguish Turkish dotted and dotless letters, including `i` and `ı`.

## Technical highlights

- **Swift 6 and SwiftUI** for the app, with **SwiftData** for local storage and String Catalogs for Russian and English interface text.
- **Supabase Auth and PostgreSQL** for accounts, progress sync and leagues. Row Level Security scopes progress to its owner. The app keeps guest and signed-in profiles separate and restores lesson completions without awarding XP again.
- **Swift Testing and XCTest** cover lesson validation, navigation, progress restoration and the main UI flows.

## Run in Xcode

1. Open `Miko.xcodeproj` in Xcode 16.4 or later.
2. Select the **Miko** scheme and an iPhone simulator running iOS 18.0 or later.
3. Press **Run** and complete onboarding. The course can be tried as a guest without creating an account.
4. To test registration or cloud sync, configure your own Supabase project using [the backend setup guide](SUPABASE_SETUP.md). A fresh checkout has no backend configured.

For a physical device, select your own Apple development team in Xcode's **Signing & Capabilities** settings.

This is a portfolio beta. Simulator coverage includes the main lesson flows. Audio and speech behavior on physical hardware still need verification.

The bundled [Lexend typeface](https://github.com/googlefonts/lexend) is distributed under the [SIL Open Font License 1.1](Miko/Resources/Fonts/OFL-Lexend.txt).
