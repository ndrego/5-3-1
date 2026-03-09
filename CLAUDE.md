# 531 Strength

## Project Overview
Personal iOS + watchOS app for tracking the Wendler 5/3/1 weightlifting program. SwiftUI + SwiftData, Swift 6, iOS 17+, watchOS 10+, no external dependencies.

## Build & Run
```bash
# Regenerate Xcode project after adding/removing files
xcodegen generate

# Build from CLI
xcodebuild -project FiveThreeOne.xcodeproj -scheme FiveThreeOne -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Open in Xcode
open FiveThreeOne.xcodeproj
```

## Architecture
- **SwiftUI + SwiftData**, MVVM where needed (simple views bind directly to models)
- **Swift 6 strict concurrency** — capture values before crossing isolation boundaries in `Task { @MainActor }`
- **No external dependencies** — keep it that way
- XcodeGen (`project.yml`) generates the `.xcodeproj` — don't hand-edit `project.pbxproj`
- **HealthKit** for heart rate streaming and saving workouts to Apple Health
- **WatchConnectivity** for bidirectional phone ↔ watch communication

## Project Structure
```
FiveThreeOne/
  App/            Entry point, tab navigation, onboarding flow
  Models/         SwiftData @Model classes + enums (Cycle, CompletedWorkout, Exercise, etc.)
  ViewModels/     Only where views need non-trivial logic
  Views/          Organized by feature: Dashboard, Workout, History, Setup, Import, Templates, Components
  Utilities/      ProgramEngine, PlateCalculator, StrongImporter, BackupManager, HeartRateManager
  Connectivity/   PhoneConnectivityManager (WatchConnectivity phone side)
  Assets.xcassets Asset catalog (app icon, accent color)
  Preview Content Sample data for SwiftUI previews

FiveThreeOneWatch/
  Views/          WatchHomeView (workout display, HR, timer)
  WatchWorkoutManager   - HealthKit workout session, HR streaming, simulator HR simulation
  WatchConnectivityManager - WatchConnectivity watch side
```

## Key Design Decisions
- **ProgramEngine** computes all sets from training max + week number. Percentages are hardcoded constants — the 5/3/1 program structure is not user-configurable data.
- **CompletedSet** and **ExercisePerformance** are `Codable` structs stored inside `CompletedWorkout` (not separate @Models) to avoid SwiftData relationship issues.
- **One main lift per workout day** — standard 5/3/1 assumption. Templates can have multiple exercises (main + accessories).
- **Cycle state is implicit** — determined by counting completed workouts, not a state machine.
- All weights round to nearest 5 lbs (configurable in UserSettings).
- **Training volume** = weight × reps (excluding warmup), doubled for unilateral exercises.
- **Calorie estimation** uses Keytel et al. (2005) gender-specific equations from heart rate, age, weight, and sex.
- **Screen stays on** during active workouts via `isIdleTimerDisabled`.
- **Weight/reps input fields** use custom string-backed fields (not `TextField(value:format:.number)` which rejects intermediate input).

## 5/3/1 Program Variants
All six are supported: Standard, BBB, FSL, 5s PRO, BBB Beefcake, SSL. Logic lives in `ProgramEngine.swift` and `ProgramVariant.swift`.

## Strong App Import
`StrongImporter.swift` parses Strong's CSV export format:
`Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE`

- Groups all exercises from the same session (same timestamp) into one `CompletedWorkout` with multiple `ExercisePerformance` entries
- Imports both main lifts and accessory exercises as workout history
- Parses duration, detects unilateral exercises
- Imported workouts get `cycleNumber: 0, weekNumber: 0` since original cycle/week context is unknown

## Backup & Restore
`BackupManager.swift` exports/imports all app data as versioned JSON. Users save to iCloud Drive or Files via the system file picker. Restore replaces all existing data.

## Watch App
The watch companion shows live workout context (current exercise, set, weight, reps), allows completing sets and stopping timers from the wrist, and streams heart rate. Communication is bidirectional via `WCSession`. The watch app is embedded in the iOS bundle.

## Conventions
- Keep models simple — avoid deeply nested SwiftData relationships
- Use `Lift` enum (not strings) for the four main lifts everywhere
- Accessory exercises use the `Exercise` @Model with push/pull/singleLegCore categories
- Prefer inline computation over stored derived data
- Large tap targets in workout views — app must be usable one-handed in the gym
- For Swift 6 concurrency: extract values from non-Sendable types before crossing isolation boundaries

## Commit Messages
Use conventional style: short summary line describing the "why", not just the "what". No prefix tags needed.
