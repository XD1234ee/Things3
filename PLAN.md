# Plan: a daily planning and focus app for Things 3 (macOS)

Working name: **Daybreak**. It's a placeholder and can be renamed.

## 1. Product goal

Things 3 is very good at *capturing* and *organizing* tasks. It doesn't help much with
*choosing what to do today* or *staying on one task at a time*. Daybreak sits next to
Things and adds a daily **Plan → Do → Reflect** loop:

1. **Plan.** Every day starts **empty**. You choose a few tasks from Things (your pool of
   ideas), put them in order, and *begin the day*.
2. **Do.** One task at a time. A focus session fills the screen with the current task and
   a timer.
3. **Reflect.** The day has an **end**. A wrap-up shows what you finished and how long you
   focused. Anything unfinished goes back to the pool, so nothing piles up as overdue. The
   day is saved to a journal.

Things stays the **source of truth** for tasks. Daybreak only stores what Things doesn't
have: the plan order, time estimates, focus sessions and the journal.

### Inspiration: Ivy (semantical.com)
Ivy is a planner for iPhone and Mac by Semantical. It works from its *own* list of ideas
and from Apple Reminders. It doesn't connect to Things. Daybreak brings the same loop to
people who use Things. These are the Ivy ideas we adopt:

| Ivy concept | Daybreak equivalent |
|---|---|
| The day starts empty; you choose from your ideas | The planner starts empty. Things lists (Today, Inbox, Anytime, deadlines, tags) are the idea pool. |
| "Slide to Begin Day" | A deliberate *Begin Day* gesture that locks in the plan and starts focus |
| Focus Timer fills the screen with one task | A full-screen or floating focus view showing one task only |
| The day ends; leftovers become ideas again and nothing is overdue | *End Day*: leftovers leave Things Today (back to Anytime) by default, so Today doesn't keep growing |
| Wrap-up and journal | A summary of completed tasks and focus time, plus a short note, saved to a journal |
| Calendar and Reminders integration | EventKit calendar (read-only) on the planner timeline. **Things is the only task source.** Daybreak doesn't use Reminders. |
| Screen Time "shields" that block distracting apps | **Gentle nudges** instead of hard blocks: if you switch to a distracting app during a pomodoro, a small reminder appears (see Phase 3) |
| Live Activity, voice input, Shortcuts | Menu bar item, dictation or quick add, App Intents |
| Habits (timed or count-based) | Could come later: repeating Things to-dos with a target duration or count |

Daybreak is its own product with its own name and visual design. Ivy is the inspiration
for the workflow only.

### Non-goals (v1)
- Replacing Things (no project or area management, no full task editing).
- Syncing across devices or building an iOS companion.
- Team or shared features.

## 2. Core user flows

### 2.1 Morning planning (target: under 3 minutes)
1. **An empty day.** The plan starts blank. A short prompt asks "What will make today a
   good day?" The advice is to pick about 3–6 tasks.
2. **Browse the idea pool.** Candidates come from Things, in groups: *Today*, overdue or
   soon-due deadlines, *Inbox*, *Anytime* (filterable by area, project or tag), and
   optionally `#next`. **Nothing is pre-selected**, because choosing each task is the point.
   A search box filters across all groups.
3. **Pick, order and estimate.** Add tasks with a click or the keyboard, then drag them
   into order. Estimate each one in **pomodoros** (🍅 × 1–8, where 1 = 25 min). A
   capacity bar (pomodoros planned versus pomodoros that fit in the free time left today)
   and a timeline of today's calendar events show whether the plan fits.
4. **Begin Day.** A deliberate gesture (slide or press and hold) commits the plan. Tasks
   you picked move to Things *Today*. The first focus session is offered right away.

### 2.2 Focus mode
- A floating, always-on-top panel shows **one** task: its title, its project or area,
  its notes, and a checklist you can tick off.
- A **Pomodoro timer**: 25 min focus and 5 min short break by default, with a 15 min
  long break after every 4 pomodoros. All lengths can be changed. The panel shows
  pomodoros done and estimated for the current task (for example 🍅🍅◻︎). Breaks are
  offered automatically and can be skipped. Finishing a task early ends the pomodoro and
  counts it.
- Actions:
  - **Complete** (⌘↩): marks the task done in Things and moves to the next task.
  - **Skip / later** (⌘→): moves the task to the end of the plan.
  - **Defer** (⌘D): moves the task to Tomorrow in Things and removes it from the plan.
  - **Open in Things** (⌘O): opens the task with `things:///show?id=…`.
  - **Break down**: adds checklist items through the Things URL scheme.
- A compact menu bar item shows the current task and the time left.
- A global hotkey (for example ⌥Space) shows or hides the focus panel.
- Optional: turn on a macOS Focus (Do Not Disturb) during sessions through a Shortcut.

- **Full-screen mode** (Ivy's style): the task and the timer only, on a calm background.
  Esc shrinks it to the floating panel.

### 2.3 End Day and wrap-up
- **End Day** is a deliberate action. Daybreak also reminds you at a time you choose.
- The wrap-up shows completed and planned tasks, total focus time, focus time per task,
  and estimated versus actual time.
- **Nothing becomes overdue.** Unfinished planned tasks **always go back to Things
  *Anytime*** (they leave Today) and wait there as ideas. Each task can be changed to
  Tomorrow or Someday during the wrap-up, but there's no option to keep tasks in Today.
  Every morning starts empty. Deadlines in Things are left alone.
- A one-line reflection ("How did today go?") is saved with the day's summary in the
  **journal**.
- A journal and history view lists past days, focus time and tasks completed. Streaks
  are optional.

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
- **Notifications:** UserNotifications for "pomodoro done", "break over" and reminders
  to plan or end the day.
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
- **Distribution: personal use only, for now.** The app is built and run from Xcode
  with your free Apple ID "Personal Team" signing, or archived and signed ad hoc and
  copied to `/Applications`. It isn't sandboxed and uses the hardened runtime with the
  `com.apple.security.automation.apple-events` entitlement. You don't need a paid
  Developer account, notarization, Sparkle or the App Store.
  - If you share it later, add Developer ID signing, notarization and a DMG. A Mac App
    Store build would mean dropping the SQLite reader and using
    `com.apple.security.scripting-targets`.
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

### Phase 1: MVP, the full Plan → Do → Reflect loop at its simplest (about 1 week)
- Menu bar app, AppleScript reader and writer, Settings with the auth token.
- An empty-day planner. The idea pool is Things *Today* and *Anytime*. Reorder, add
  estimates, then Begin Day.
- Focus panel with the Pomodoro timer (focus, short break, long break), Complete, Skip and Open in Things, and the global hotkey.
- A basic End Day: completed versus planned, and leftovers sent back to Anytime.
- Local persistence of the plan. Polling and reconciliation.
- **Exit criteria:** you can use it for a whole workday without opening Things to tick tasks off.

### Phase 2: Full planning ritual (about 1 week)
- The complete idea pool: Inbox, deadlines, filters by area, project or tag, and search.
- Defer actions (Tomorrow, Evening, Someday) written back to Things.
- EventKit capacity bar and a timeline of the day.
- Full-screen focus mode.
- Notifications: plan reminder, time's up, breaks, End Day reminder.

### Phase 3: Reflect, journal and distraction nudges (about 1–2 weeks)
- A full wrap-up screen, the reflection prompt and the journal or history view.
- Estimated versus actual time.
- **Distraction nudges:** the user keeps a list of distracting apps. During a pomodoro,
  Daybreak watches the frontmost app with
  `NSWorkspace.didActivateApplicationNotification`. When a listed app comes to the front,
  a small non-blocking banner appears near the focus panel ("You're focusing on *X* · 14:32
  left") with *Back to task* and *Allow 5 min* buttons. Nothing is blocked or hidden.
  Distracting websites would need browser access through AppleScript, so they're left
  out of v1. An optional Shortcut can turn on a macOS Focus mode during pomodoros.
- App Intents and Shortcuts ("Begin Day", "Start focus", "Complete current task", "End Day").

### Phase 4: Polish and release
- Optional SQLite fast reader with FSEvents.
- Onboarding, empty states, error handling when Things is closed, dark mode, accessibility
  (VoiceOver, keyboard-only use).
- A README with build-and-run steps for your own Mac. (Signing, notarization and
  updates can wait until you want to share the app.)

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

## 9. Decisions (confirmed)
1. **End Day:** unfinished tasks go back to **Anytime**.
2. **Distractions:** nudge only, never a hard block.
3. **Task source:** **only Things**. No Reminders.
4. **Distribution:** **personal use for now**, built locally in Xcode.
5. **Timer:** **Pomodoro** (25/5, with a 15 min long break after 4 pomodoros; all
   adjustable). Estimates are in pomodoros.

## 10. Still open (sensible defaults chosen; change if you want)
- Calendar timeline: **read-only display in v1**, with no time-blocking back to the calendar.
- Writing tags to Things: **no tags in v1**. The plan lives in Daybreak, and the tasks
  you picked are in Things Today, so Things on iPhone still shows them.
