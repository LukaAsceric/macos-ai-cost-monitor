# Standalone Settings and Console Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a standalone macOS settings window with a Stats-like sidebar and a privacy-safe live console that explains how OpenRouter reporting is fetched, filtered, aggregated, cached, and displayed.

**Architecture:** Keep the menu-bar popover focused on the current report. Introduce a retained `SettingsWindowController` owned by `AppDelegate`, opened from the app menu, and host a SwiftUI `SettingsRootView` with sidebar sections. Add an in-memory `AppLogStore` observable object; log only lifecycle, request metadata, response counts, selected report date, aggregation totals, cache outcomes, and sanitized errors—never keys, response bodies, or authorization headers.

**Tech Stack:** Swift 5.9, macOS 13+, SwiftUI, AppKit, Combine, XCTest.

---

### Task 1: Add the logging seam

**Files:**
- Create: `Sources/MacOSAICostMonitor/State/AppLogStore.swift`
- Modify: `Sources/MacOSAICostMonitor/State/CostMonitorModel.swift`
- Test: `Tests/MacOSAICostMonitorTests/AppLogStoreTests.swift`

**Steps:**
1. Write tests for bounded in-memory entries, severity filtering, clear, and redaction of key-like strings.
2. Run the focused tests and verify they fail because `AppLogStore` does not exist.
3. Implement `LogLevel`, `LogEntry`, and `AppLogStore` as a MainActor `ObservableObject` with max 500 entries.
4. Add a `log` dependency to `CostMonitorModel` and log refresh start, cache load, Keychain status (without values), request date/range, response row count, selected report date, aggregation totals, cache result, and sanitized failures.
5. Run focused tests and then the full suite.

### Task 2: Add a retained standalone settings window

**Files:**
- Create: `Sources/MacOSAICostMonitor/UI/SettingsRootView.swift`
- Create: `Sources/MacOSAICostMonitor/UI/SettingsWindowController.swift`
- Modify: `Sources/MacOSAICostMonitor/AppDelegate.swift`
- Modify: `Sources/MacOSAICostMonitor/UI/StatusBarController.swift`
- Modify: `Sources/MacOSAICostMonitor/App.swift`

**Steps:**
1. Write a testable settings-window factory/ownership seam where practical.
2. Implement a retained `NSWindowController` with `NSHostingController(rootView:)`, title, minimum size, toolbar/standard resizability, and activation/focus behavior.
3. Build `SettingsRootView` with a `NavigationSplitView` sidebar: General, OpenRouter, Reporting, Console.
4. Move key/reporting controls into section views while preserving existing Keychain and `ReportingPreferences` behavior.
5. Add `Settings…` to the application menu and make the popover Settings button open the standalone window instead of a sheet.
6. Run macOS build/tests and manually verify one window instance, reopening/focus, menu-bar operation, and app termination.

### Task 3: Build the console view

**Files:**
- Create: `Sources/MacOSAICostMonitor/UI/ConsoleView.swift`
- Modify: `Sources/MacOSAICostMonitor/UI/SettingsRootView.swift`

**Steps:**
1. Add a console view with monospaced rows, timestamps, level badges, search/filter field, level picker, Copy, and Clear actions.
2. Show an empty state explaining that logs contain metadata only and never secrets.
3. Add live updates from `AppLogStore` and preserve scroll position sensibly.
4. Add accessibility labels and a clear visual distinction between debug/info/warning/error.
5. Manually verify error, network, no-data, cache, and successful refresh scenarios through logs.

### Task 4: Add verification and documentation

**Files:**
- Modify: `Tests/MacOSAICostMonitorTests/*`
- Modify: `README.md`
- Modify: `Scripts/build-app.sh` only if needed for app-menu/window behavior

**Steps:**
1. Add tests proving secret values and Authorization headers never enter log entries.
2. Add tests for report-date selection and cache diagnostics.
3. Run `swift build`, `swift test`, `bash Scripts/build-app.sh`, `plutil -lint dist/MacOSAICostMonitor.app/Contents/Info.plist`, and `codesign --verify --deep --strict dist/MacOSAICostMonitor.app` on macOS.
4. Run static checks on Linux if macOS is unavailable.
5. Update README with standalone settings access, console privacy guarantees, and the signed `.app` launch requirement.
6. Commit with `feat: add standalone settings and diagnostic console` and push `main`.

**Expected macOS verification:** build succeeds; all tests pass; Settings window opens from the app menu and popover; Console updates after refresh; copied logs contain no credentials or response bodies.

**Known limitation:** AppKit window and Keychain prompt behavior cannot be fully verified on Linux; those checks require macOS.

---

## Key Design Decisions

- The console is diagnostic, not a raw HTTP dump.
- Never log management keys, bearer tokens, full request URLs containing secrets, response bodies, or model/API key identifiers that could be sensitive.
- The existing menu-bar popover remains compact; detailed configuration lives in the standalone window.
- Existing UTC/completed-day semantics remain explicit in the Reporting section.
- Settings window ownership is retained by `AppDelegate` to prevent duplicate windows and premature deallocation.

## Interaction Sketch

```text
App menu → Settings…
              ┌─────────────────────────────────────────────┐
              │ General / OpenRouter / Reporting / Console  │
              │                                             │
              │  selected section content                  │
              │                                             │
              │  [Save] [Refresh now]                       │
              └─────────────────────────────────────────────┘

Menu-bar popover → Settings → focuses the same window
```

## Rollback

If the standalone window introduces runtime issues, retain the existing popover controls and disable only the new window entry while keeping `AppLogStore` and diagnostics; both are independently useful and low-risk.

## Completion Checklist

- [ ] Plan saved
- [ ] Logging tests written and passing
- [ ] Standalone window opens and is retained
- [ ] Sidebar sections work
- [ ] Console displays sanitized diagnostics
- [ ] Copy/Clear/filter work
- [ ] Full macOS tests/build pass
- [ ] README updated
- [ ] Commit pushed
- [ ] No secrets in logs or repository

## Suggested Commits

1. `feat: add sanitized diagnostic logging`
2. `feat: add standalone settings window`
3. `feat: add diagnostic console view`
4. `docs: document settings and diagnostics`

Frequent commits keep window and logging changes independently reversible.

## Scope Review

The requested standalone window, sidebar navigation, diagnostics, and console are in scope. A full historical charting/trend engine, local-day reconstruction, and raw request/response inspector are intentionally out of scope for this iteration.

## Risks

- `NavigationSplitView` and AppKit hosting behavior differ between macOS 13 and current macOS releases; keep the view hierarchy simple and verify on macOS 13 if possible.
- `NSWindowController` ownership must remain in `AppDelegate`; local-only controllers may disappear immediately.
- Combine/Swift concurrency callbacks must dispatch UI updates to `MainActor`.
- Logging must be metadata-only and should redact aggressively rather than attempting to log complete API diagnostics.

## Handoff

After the plan is saved, execution should proceed task-by-task with the `executing-plans` skill or a fresh subagent-driven implementation session.

## Plan complete

Plan complete and saved to `docs/plans/2026-08-17-settings-console.md`. Two execution options:

1. **Subagent-Driven (this session)** — dispatch a fresh subagent per task, review between tasks, and iterate quickly.
2. **Parallel Session (separate)** — open a new session with `executing-plans` and execute from the plan with checkpoints.

For this repository, the recommended option is **Subagent-Driven (this session)** because the current macOS implementation is small and the standalone window touches AppKit lifecycle code that benefits from immediate review.

## Source Notes

The requested Stats-style interaction was interpreted as: a persistent preferences window, sidebar navigation, and a diagnostics/console surface. The external URLs were not treated as authoritative API sources; the app's existing OpenRouter documentation and security constraints remain authoritative for data semantics and credential handling.

## Verification Notes

On Linux, use balanced-delimiter/static checks, `git diff --check`, plist parsing, shell syntax, and secret scans. On macOS, the authoritative checks are `swift build`, `swift test`, app bundle launch, window focus/reopen, Keychain behavior, and `codesign --verify --deep --strict`.

## Future Extensions

- Export sanitized logs to a file.
- OSLog integration with Console.app, with privacy annotations.
- Multiple provider settings pages.
- Historical charts once provider data semantics support reliable date ranges.
- User-selectable local display timezone with explicit UTC data-basis labeling.

## Non-Goals

- No credentials in logs.
- No automatic Keychain ACL weakening.
- No raw API response body viewer.
- No claim of live local-day spend from completed UTC-day activity data.

## Review Questions

- Does a first-time user find Settings without opening the popover?
- Can they understand why a displayed date differs from their local day?
- Can they diagnose missing data from the console without seeing secrets?
- Can they copy logs for support without sanitizing manually?
- Does opening Settings focus the existing window instead of creating duplicates?

## End State

A signed `.app` opens as a menu-bar utility. The menu-bar popover shows the current report. `Settings…` opens a retained, resizable settings window with a Stats-like sidebar. The Console section shows a searchable, bounded, metadata-only explanation of each refresh and its result.