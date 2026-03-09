# 531 Strength

A personal iOS + watchOS app for tracking the Wendler 5/3/1 weightlifting program.

## Features

- **All 6 program variants**: Standard, BBB, FSL, 5s PRO, BBB Beefcake, SSL
- **Auto-calculated weights**: Enter training maxes, get exact weights per set with per-lift TM percentages
- **Plate calculator**: Tap-to-toggle colored plate diagrams on any barbell set
- **AMRAP tracking**: Log your plus-set reps with estimated 1RM (Epley formula)
- **Auto-progression**: +5 lbs upper body, +10 lbs lower body between cycles (configurable)
- **Configurable warmup sets**: Add/remove warmup sets with custom percentages and reps
- **Rest timers**: Per-set-type rest timers (main/supplemental/accessory) with optional HR-based recovery
- **Training volume**: Per-exercise and total workout volume tracking, with unilateral exercise support (doubled for single-arm/leg work)
- **Workout templates**: Customizable workout templates with superset grouping
- **Exercise library**: Common 5/3/1 accessories organized by push/pull/legs+core
- **Apple Watch companion**: Live workout tracking, set completion, timer control, and heart rate monitoring from your wrist
- **HealthKit integration**: Heart rate streaming during workouts, calorie estimation (Keytel et al. formula with age/weight/sex), and completed workouts saved to Apple Health
- **Strong app import**: Import full workout history from Strong's CSV export — all exercises, not just main lifts
- **Backup & restore**: Export all data to JSON, save to iCloud Drive or Files for safekeeping
- **Screen stays on**: Display stays awake during active workouts
- **Appearance**: System, light, or dark theme (defaults to dark)
- **Privacy**: No analytics, no tracking, no data leaves your device (except optional HealthKit sync)

## Tech Stack

- Swift 6 / SwiftUI (iOS 17+, watchOS 10+)
- SwiftData for local persistence
- HealthKit for heart rate and workout sync
- WatchConnectivity for phone/watch communication
- XcodeGen for project generation
- No external dependencies

## Project Structure

```
FiveThreeOne/
  App/            - Entry point, tab navigation, onboarding
  Models/         - Cycle, CompletedWorkout, Exercise, UserSettings, WorkoutTemplate
  ViewModels/     - (as needed)
  Views/          - Dashboard, Workout, History, Settings, Import, Templates, Components
  Utilities/      - ProgramEngine, PlateCalculator, StrongImporter, BackupManager, HeartRateManager
  Connectivity/   - PhoneConnectivityManager (WatchConnectivity)

FiveThreeOneWatch/
  Views/          - WatchHomeView
  WatchWorkoutManager, WatchConnectivityManager
```

## Building

```bash
# Regenerate Xcode project (required after adding/removing files)
xcodegen generate

# Build
xcodebuild -project FiveThreeOne.xcodeproj -scheme FiveThreeOne \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Open in Xcode
open FiveThreeOne.xcodeproj
```

## 5/3/1 Program Reference

| Week | Scheme | Set 1 | Set 2 | Set 3 |
|------|--------|-------|-------|-------|
| 1 | 5/5/5+ | 65% x5 | 75% x5 | 85% x5+ |
| 2 | 3/3/3+ | 70% x3 | 80% x3 | 90% x3+ |
| 3 | 5/3/1+ | 75% x5 | 85% x3 | 95% x1+ |
| 4 | Deload | 40% x5 | 50% x5 | 60% x5 |

Percentages are of Training Max (typically 85-90% of 1RM).
