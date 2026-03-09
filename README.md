# 5/3/1 Workout Tracker

A personal iOS app for tracking the Wendler 5/3/1 weightlifting program.

## Features

- **All 5/3/1 variants**: Standard, BBB, FSL, 5s PRO, BBB Beefcake, SSL
- **Auto-calculated weights**: Enter training maxes, get exact weights per set
- **Plate calculator**: Shows which plates to load, inline per set
- **AMRAP tracking**: Log your plus-set reps with estimated 1RM
- **Auto-progression**: +5 lbs upper body, +10 lbs lower body between cycles
- **Strong app import**: Import your workout history from Strong's CSV export
- **Exercise library**: Common 5/3/1 accessories organized by push/pull/legs+core

## Tech Stack

- Swift / SwiftUI (iOS 17+)
- SwiftData for local persistence
- No external dependencies

## Project Structure

```
FiveThreeOne/
  App/          - Entry point, navigation
  Models/       - Cycle, CompletedWorkout, Exercise, UserSettings
  ViewModels/   - (as needed)
  Views/        - Dashboard, Workout, History, Settings, Import
  Utilities/    - ProgramEngine, PlateCalculator, StrongImporter
```

## 5/3/1 Program Reference

| Week | Scheme | Set 1 | Set 2 | Set 3 |
|------|--------|-------|-------|-------|
| 1 | 5/5/5+ | 65% x5 | 75% x5 | 85% x5+ |
| 2 | 3/3/3+ | 70% x3 | 80% x3 | 90% x3+ |
| 3 | 5/3/1+ | 75% x5 | 85% x3 | 95% x1+ |
| 4 | Deload | 40% x5 | 50% x5 | 60% x5 |

Percentages are of Training Max (typically 90% of 1RM).
