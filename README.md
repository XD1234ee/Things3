# Daybreak

A macOS menu bar app that adds a daily **Plan → Do → Reflect** loop on top of
[Things 3](https://culturedcode.com/things/):

- **Plan.** Every day starts empty. Pick a few to-dos from Things, put them in
  order, estimate each in pomodoros, then *hold to Begin Day*. The picked tasks
  move to Things Today.
- **Do.** A floating focus panel shows one task at a time with a Pomodoro timer
  (25/5, with a long break after every 4). Mark the task done (it's completed in
  Things), push it to later, or postpone it to Tomorrow or Someday.
- **Reflect.** End the day with a wrap-up: what got done and how long you
  focused, plus a one-line note for your journal. Unfinished tasks go back to
  Anytime in Things, so nothing piles up as overdue.

The workflow is inspired by [Ivy](https://semantical.com/). See [PLAN.md](PLAN.md)
for the full plan and roadmap.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later
- Things 3 for Mac
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and run

```sh
xcodegen generate        # creates Daybreak.xcodeproj from project.yml
open Daybreak.xcodeproj
```

In Xcode, select the **Daybreak** target. Under *Signing & Capabilities*, choose
your Personal Team (your free Apple ID works). Then press ⌘R. Daybreak appears in
the menu bar; it has no Dock icon.

The first time Daybreak reads your lists, macOS asks whether it may control
Things. Allow it. You can change this later in System Settings → Privacy &
Security → Automation.

To keep a copy in `/Applications`, use *Product → Archive → Distribute App →
Custom → Copy App*.

## Try the Things connection first (Phase 0)

Before building the app, you can check that reading from and writing to Things
works on your Mac, and how fast it is:

```sh
Scripts/spike.sh           # read-only: connection check and read timings
Scripts/spike.sh --write   # also creates, moves, completes and deletes one test to-do
```

## Project layout

```
DaybreakCore/          Swift package: all logic, tested without the UI
  Sources/DaybreakCore/
    Resources/things.js   JavaScript for Automation bridge to Things (run through osascript)
    Things/               ThingsClient protocol, AppleScript client, in-memory fake
    Domain/               DayPlan, PomodoroEngine, IdeaPool, DayCoordinator
    Persistence/          AppState, JSON file store
  Tests/                  XCTest suite
Daybreak/              The SwiftUI app (menu bar, planner, focus panel, wrap-up, settings)
project.yml            XcodeGen project spec
Scripts/spike.sh       Phase 0 connection test
```

## Tests

```sh
cd DaybreakCore && swift test
```

CI (GitHub Actions, macOS) runs the tests and builds the app on every push.

## Where data lives

- **Tasks** stay in Things. Daybreak only completes or moves the to-dos you plan.
- **Plan, focus time and journal** are saved in
  `~/Library/Application Support/Daybreak/state.json`.
