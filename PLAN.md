# Plan: a daily planning and focus app for Things 3 (macOS)

Working name: **Daybreak**. It's a placeholder and can be renamed.

## 1. Product goal

Things 3 is very good at *capturing* and *organizing* tasks. It doesn't help much with
*choosing what to do today* or *staying on one task at a time*. Daybreak sits next to
Things and adds two rituals and one mode:

1. **Plan the day.** A short guided morning flow: review candidates, pick a realistic
   set, put them in order, estimate time, and commit.
2. **Focus.** A minimal "one task" view that stays on top of other windows, with a timer.
   Finishing or skipping a task moves you to the next one.
3. **Shut down.** An end-of-day review: what got done, what rolls over, and a clean slate
   for tomorrow.

Things stays the **source of truth** for tasks. Daybreak only stores what Things doesn't
have: the plan order, time estimates, focus sessions and history.

### Non-goals (v1)
- Replacing Things (no project or area management, no full task editing).
- Syncing across devices or building an iOS companion.
- Team or shared features.

## 2. Core user flows

### 2.1 Morning planning (target: under 3 minutes)
1. **Gather.** Show candidates in groups: Things *Today*, overdue deadlines, *Inbox*,
   tasks with a deadline in the next 3 days, and (optionally) tasks tagged `#next`.
2. **Pick.** Click or press a key to add a task to today's plan or leave it out.
   Things *Today* items are pre-selected.
3. **Order and estimate.** Drag to reorder. Give each task an estimate (15m, 30m, 1h,
   2h, or a custom value). A capacity bar compares the planned total with the free time
   left today, which can come from the calendar.
4. **Commit.** Tasks you picked are moved to Things *Today*. Tasks you left out of
   *Today* can be deferred ("This Evening", "Tomorrow", or "Someday"). The plan is saved
   in Daybreak.

### 2.2 Focus mode
- A floating, always-on-top panel shows **one** task: its title, its project or area,
  its notes, and a checklist you can tick off.
- A timer counts down from the estimate, or runs as a Pomodoro (25/5).
- Actions:
  - **Complete** (⌘↩): marks the task done in Things and moves to the next task.
  - **Skip / later** (⌘→): moves the task to the end of the plan.
  - **Defer** (⌘D): moves the task to Tomorrow in Things and removes it from the plan.
  - **Open in Things** (⌘O): opens the task with `things:///show?id=…`.
  - **Break down**: adds checklist items through the Things URL scheme.
- A compact menu bar item shows the current task and the time left.
- A global hotkey (for example ⌥Space) shows or hides the focus panel.
- Optional: turn on a macOS Focus (Do Not Disturb) during sessions through a Shortcut.

### 2.3 End-of-day shutdown
- Shows completed and planned tasks, focus time per task, and estimated versus actual time.
- Leftover tasks can stay in Today, move to Tomorrow, or move to Someday.
- An optional single-line journal note.
- A daily streak and history view (later phase).

## 3. Integrating with Things 3

Things on macOS can be reached in three ways. Daybreak uses all three, each for the job
it does best.

| Mechanism | Read | Write | Pros | Cons |
|---|---|---|---|---|
| **AppleScript / Scripting Bridge** (`tell application "Things3"`) | ✅ lists, to-dos, projects, areas, tags, notes, dates | ✅ complete, cancel, move to list, create, set properties | Officially supported and stable | Slow on large lists; needs Automation permission |
| **URL scheme** (`things:///add`, `update`, `json`, `show`) | ❌ | ✅ add, update, checklist items, `when=`, `deadline=` | Officially documented, fast, rich updates | Updating needs the user's *auth token*; can't read anything; Things comes to the front unless `reveal=false` |
| **SQLite database** (read-only), in `~/Library/Group Containers/JLMPQHK86H.com.culturedcode.ThingsMac/…/main.sqlite` | ✅ very fast, includes Today ordering and checklist items | ❌ never write to it | Instant reads, good for polling | Undocumented schema that can change; not allowed in the Mac App Store sandbox; needs Full Disk Access or a folder grant |

**Decision:**
- **Reads:** an `AppleScriptReader` as the default. It is supported, works when sandboxed,
  and is enough for lists of a few hundred items. An optional `SQLiteReader` can be
  switched on in settings for speed and for detecting changes. Both implement the same
  `ThingsReader` protocol.
- **Writes:** AppleScript for complete, cancel and move to Today, Tomorrow or Someday.
  The URL scheme (with the auth token from Things → Settings → General → Enable Things
  URLs) for checklist items, notes and deadlines, using `reveal=false`.
- **Detecting changes:** Things doesn't send notifications when data changes. Daybreak
  re-reads when its windows become key and every 30–60 s while it's active. With the
  SQLite reader on, it also watches `main.sqlite-wal` with FSEvents so changes show up
  almost immediately.
- **IDs:** use the stable Things to-do `id` everywhere. If a planned ID disappears
  (deleted or completed elsewhere), reconcile it gracefully.

### Things data we need
`id, title, notes, status, project/area name, tags, when/start (today/evening),
deadline, checklist items, creation date`, plus the order within Today (from the SQLite
`todayIndex`, or the order AppleScript returns for `list "Today"`).

> Note: Things doesn't let other apps change the order of *Today* through any public
> API. Daybreak keeps **its own plan order** and shows it in the app and in focus mode.
> It does not try to reorder the Today list inside Things.

## 4. Technical architecture

- **Language/UI:** Swift 6 and SwiftUI. AppKit is used where SwiftUI falls short: an
  `NSPanel` for the floating focus window and a global hotkey.
- **Minimum OS:** macOS 14 Sonoma, for `MenuBarExtra`, SwiftData, `@Observable` and
  modern App Intents.
- **App shape:** a menu bar app with an optional Dock icon. The windows are Planner,
  Focus panel, Shutdown and Settings.
- **Local storage:** SwiftData (or GRDB) for `DayPlan`, `PlannedTask` (Things ID, order,
  estimate, status), `FocusSession` (start, end, task ID, outcome) and `Settings`.
- **Calendar (optional):** EventKit for read-only access to today's events, used to
  compute free time and show a timeline in the planner.
- **Notifications:** UserNotifications for "time's up", "break over" and reminders to
  plan or shut down.
- **Shortcuts / App Intents:** "Start focus", "Complete current task", "What am I
  working on?" These also let macOS Focus modes and Stream Deck trigger Daybreak.
- **Dependencies (minimal):** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
  for the hotkey, and GRDB only if the SQLite reader is built.

```
Daybreak/
  App/                 DaybreakApp.swift, AppDelegate, MenuBarExtra
  Features/
    Planner/           PlannerView, PlannerViewModel, CandidateList, CapacityBar
    Focus/             FocusPanel (NSPanel), FocusView, TimerEngine
    Shutdown/          ShutdownView, ShutdownViewModel
    Settings/          SettingsView (auth token, reader choice, hotkeys, timer)
  Things/
    ThingsModels.swift ThingsTodo, ThingsList, ThingsProject…
    ThingsReader.swift protocol + AppleScriptReader + SQLiteReader
    ThingsWriter.swift protocol + AppleScriptWriter + URLSchemeWriter
    ThingsSync.swift   polling / FSEvents, reconciliation
  Domain/              DayPlan, PlannedTask, FocusSession, PlanService
  Persistence/         SwiftData container
  Calendar/            CalendarService (EventKit)
  Intents/             App Intents
DaybreakTests/         unit tests with FakeThingsReader/Writer
```

Key rules:
- All Things access goes through the `ThingsReader` and `ThingsWriter` protocols. The UI
  and the domain code are tested against fakes, so most of the logic can be tested
  without Things installed.
- AppleScript runs off the main thread, through `NSAppleScript` or the `osascript`
  process, with timeouts. Errors are mapped to typed cases: `notInstalled`,
  `permissionDenied`, `timeout`.

## 5. Permissions, signing and distribution

- **Automation permission:** set `NSAppleEventsUsageDescription` in Info.plist. macOS
  asks the user once, the first time Daybreak controls Things.
- **Sandboxing:**
  - v1 is distributed **outside the Mac App Store**. It's signed with Developer ID,
    notarized, uses the hardened runtime with the `com.apple.security.automation.apple-events`
    entitlement, and ships as a DMG, optionally with Sparkle for updates. This keeps the
    SQLite reader possible and avoids App Store review risk around controlling another app.
  - Later, a Mac App Store build is possible if the SQLite reader is dropped. It would use
    `com.apple.security.scripting-targets` (or a temporary-exception entitlement) for
    `com.culturedcode.ThingsMac`.
- **Full Disk Access** is needed only if the user turns on the SQLite reader. An
  onboarding screen explains why.
- **Onboarding checklist:** Things is installed → grant Automation → paste the Things URL
  auth token → (optional) grant Calendar access → (optional) turn on the fast reader.

## 6. Delivery phases

### Phase 0: Spike (1–2 days)
- Script prototypes: read Today, Inbox and Upcoming with AppleScript and JXA, and time
  them on a real library. Complete a task, move a task to Today, and add a checklist item
  through the URL scheme.
- Look at the SQLite schema (the `TMTask` and `TMChecklistItem` tables) and confirm the
  Today ordering fields.
- **Exit criteria:** a written note on read and write latency, and confirmation that each
  write operation works.

### Phase 1: MVP, "one task at a time" (about 1 week)
- Menu bar app, AppleScript reader and writer, Settings with the auth token.
- A simple planner: Things *Today* only, reorder, estimates, commit.
- Focus panel with a countdown timer, Complete, Skip and Open in Things, and the global hotkey.
- Local persistence of the plan. Polling and reconciliation.
- **Exit criteria:** you can use it for a whole workday without opening Things to tick tasks off.

### Phase 2: Full morning ritual (about 1 week)
- Candidate groups: Inbox, overdue, upcoming deadlines, `#next` tag.
- Defer actions (Tomorrow, Evening, Someday) written back to Things.
- EventKit capacity bar and a timeline of the day.
- Notifications: plan reminder, time's up, breaks.

### Phase 3: Shutdown and history (about 1 week)
- Shutdown review and rollover.
- History of focus sessions, and estimated versus actual time.
- App Intents and Shortcuts, plus the optional macOS Focus trigger.

### Phase 4: Polish and release
- Optional SQLite fast reader with FSEvents.
- Onboarding, empty states, error handling when Things is closed, dark mode, accessibility
  (VoiceOver, keyboard-only use).
- Signing, notarization, Sparkle, a landing page or README with screenshots.

## 7. Testing strategy
- **Unit tests:** `PlanService`, reconciliation and the timer engine, tested against
  `FakeThingsReader` and `FakeThingsWriter`.
- **Contract tests (manual or opt-in):** run against a real Things install that holds a
  dedicated "Daybreak Test" area. They create, read, complete and clean up test data.
- **UI tests:** XCUITest for the planner and focus flows, using the fake Things backend.
- **CI:** GitHub Actions on `macos-14` or newer runners running `xcodebuild test`. Contract
  tests are excluded because CI has no Things.

> Note: these cloud sessions run on Linux, so the Xcode project can't be built or run
> here. Code can still be written here. Building and testing happens on your Mac or in
> macOS CI.

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| AppleScript is slow with large libraries | Fetch only the lists we need, cache results, and offer the SQLite reader |
| Things' SQLite schema changes | Keep it optional, check the schema version, fall back to AppleScript |
| Today can't be reordered in Things | Keep Daybreak's own order and say so clearly in the UI |
| The user edits tasks in Things during a session | Poll or watch, reconcile by ID, and handle tasks that are already done or missing |
| Missing or wrong auth token | Detect URL-scheme failures and guide the user to the Things setting |
| Writing to Things brings it to the front | Use `reveal=false` on URLs and prefer AppleScript for silent writes |

## 9. Open questions
1. What does the Reddit inspiration post show? (It couldn't be opened from the build
   environment.) Are there specific features or a visual style to match?
2. Should time-blocking against the calendar be a core part of v1, or a later add-on?
3. Distribution: just for you, or shared publicly (Developer ID DMG versus the Mac App Store)?
4. Should we write tags back to Things (for example `#planned`, or `#focus` on the current
   task) so the plan also shows up in Things on iPhone?
5. Timer style: count down from the estimate, Pomodoro, or count up?
