# 5/3/1 Workout Tracker

## Project Overview
Personal iOS app for tracking the Wendler 5/3/1 weightlifting program. SwiftUI + SwiftData, iOS 17+, no external dependencies.

## Build & Run
```bash
# Regenerate Xcode project after adding/removing files
xcodegen generate

# Build from CLI (requires working xcodebuild)
xcodebuild -project FiveThreeOne.xcodeproj -scheme FiveThreeOne -destination 'platform=iOS Simulator,name=iPhone 16' build

# Open in Xcode
open FiveThreeOne.xcodeproj
```

## Architecture
- **SwiftUI + SwiftData**, MVVM where needed (simple views bind directly to models)
- **No external dependencies** — keep it that way
- XcodeGen (`project.yml`) generates the `.xcodeproj` — don't hand-edit `project.pbxproj`

## Project Structure
```
FiveThreeOne/
  App/            Entry point, tab navigation, onboarding flow
  Models/         SwiftData @Model classes + enums (Cycle, CompletedWorkout, Exercise, etc.)
  ViewModels/     Only where views need non-trivial logic
  Views/          Organized by feature: Dashboard, Workout, History, Setup, Import, Components
  Utilities/      Pure logic: ProgramEngine, PlateCalculator, StrongImporter
  Assets.xcassets Asset catalog (app icon, accent color)
  Preview Content Sample data for SwiftUI previews
```

## Key Design Decisions
- **ProgramEngine** computes all sets from training max + week number. Percentages are hardcoded constants — the 5/3/1 program structure is not user-configurable data.
- **CompletedSet** is a `Codable` struct stored inside `CompletedWorkout` (not a separate @Model) to avoid SwiftData relationship issues.
- **One lift per workout day** — standard 5/3/1 assumption.
- **Cycle state is implicit** — determined by counting completed workouts, not a state machine.
- All weights round to nearest 5 lbs (configurable in UserSettings).

## 5/3/1 Program Variants
All six are supported: Standard, BBB, FSL, 5s PRO, BBB Beefcake, SSL. Logic lives in `ProgramEngine.swift` and `ProgramVariant.swift`.

## Strong App Import
`StrongImporter.swift` parses Strong's CSV export format:
`Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE`

Imported workouts get `cycleNumber: 0, weekNumber: 0` since original cycle/week context is unknown.

## Conventions
- Keep models simple — avoid deeply nested SwiftData relationships
- Use `Lift` enum (not strings) for the four main lifts everywhere
- Accessory exercises use the `Exercise` @Model with push/pull/singleLegCore categories
- Prefer inline computation over stored derived data
- Large tap targets in workout views — app must be usable one-handed in the gym

## Commit Messages
Use conventional style: short summary line describing the "why", not just the "what". No prefix tags needed.
