# macOS AI Cost Monitor Implementation Plan

> **For Hermes:** Use the `subagent-driven-development` skill to implement this plan task-by-task.

**Goal:** Build a native macOS menu-bar application that displays the authenticated OpenRouter account's spend for the current available UTC day, refreshes it periodically, and provides a small detail popover with usage breakdowns.

**Architecture:** Use a native Swift executable with an AppKit `NSStatusItem` and a SwiftUI popover. Keep provider-independent domain types and aggregation logic separate from an `OpenRouterUsageProvider`; this allows additional AI services to be added later without changing the menu-bar UI. Store only the OpenRouter management key in the macOS Keychain, cache non-sensitive usage data in Application Support, and make the UI explicit when OpenRouter has not yet published current-day data.

**Tech Stack:** Swift 5.10/6, macOS 13+, SwiftUI, AppKit, Foundation `URLSession` with async/await, Security/Keychain Services, Swift Package Manager, XCTest.

---

## Product Definition

### MVP behavior

1. The app launches as an agent/menu-bar application and does not show a Dock icon.
2. The menu-bar title shows a compact cost such as `$0.42`, `$0.0042`, or `—` when no value is available.
3. Clicking the title opens a popover containing:
   - the requested UTC date;
   - total OpenRouter spend (`usage` summed across activity rows);
   - request count;
   - prompt, completion, and reasoning token totals;
   - a model/provider breakdown;
   - `Last updated` and a stale/offline indicator when appropriate.
4. The first launch presents setup for an OpenRouter **management API key**. The key is saved to Keychain, never to `UserDefaults`, the cache, logs, or source files.
5. The app refreshes automatically every five minutes while running and offers a manual refresh action.
6. Authentication, permission, rate-limit, network, malformed-response, and empty-data states are shown without discarding the last known valid result.
7. The app does not silently display yesterday's spend as today's spend.

### Important API limitation

OpenRouter's documented activity endpoint is:

```text
GET https://openrouter.ai/api/v1/activity?date=YYYY-MM-DD
```

It requires a management key and returns activity for the last 30 **completed UTC days**. The `usage` field is the OpenRouter spend for an activity row; `byok_usage_inference` is a separate estimated BYOK amount.

Therefore, “live cost of the day” cannot be promised as exact real-time local-day accounting using this endpoint alone. The MVP should request the current UTC date, label the result as a UTC day, and show `No current-day activity available yet` if the API has not published that day. If exact same-day or local-midnight accounting is mandatory, that is a follow-up architecture involving request instrumentation/proxying rather than account-level activity polling.

### Non-goals for the first release

- Direct integrations with Anthropic, OpenAI, Google, or other providers.
- Capturing requests made by arbitrary third-party applications.
- Charts, historical browsing, budgets, notifications, or App Store distribution.
- OAuth or browser-based account login.
- Counting prompts/completions locally as a substitute for OpenRouter billing data.

## Current Context and Assumptions

- The repository is currently empty; all source, tests, packaging, and documentation files must be created.
- The initial distribution target is a locally built `.app` on macOS, not the Mac App Store.
- The deployment target is macOS 13 Ventura or later so the project can use modern Swift concurrency while retaining broad menu-bar compatibility.
- OpenRouter management-key creation and permission instructions will be documented for the user; no credential will be included in the repository or test fixtures.
- Cost is represented as `Decimal` in domain code to avoid binary floating-point accumulation errors.
- The primary displayed total is OpenRouter `usage`. BYOK estimates are retained separately and shown in details but are not added to the main total in the MVP.

## Proposed Source Layout

```text
Package.swift
README.md

Resources/
  Info.plist

Sources/MacOSAICostMonitor/
  App.swift
  AppDelegate.swift
  Models/
    ActivityItem.swift
    DailyCost.swift
  Services/
    UsageProvider.swift
    OpenRouterClient.swift
    KeychainStore.swift
    UsageCache.swift
  State/
    CostMonitorModel.swift
    RefreshScheduler.swift
  UI/
    StatusBarController.swift
    DashboardView.swift
    SettingsView.swift
    CostFormatStyle.swift

Tests/MacOSAICostMonitorTests/
  Fixtures/activity-response.json
  ActivityAggregationTests.swift
  OpenRouterClientTests.swift
  CostMonitorModelTests.swift
  UsageCacheTests.swift
  TestDoubles.swift

Scripts/
  build-app.sh
```

The exact filenames may be adjusted during implementation, but provider access, aggregation, state management, and UI should remain separate responsibilities.

---

## Task 0: Validate the OpenRouter data contract before implementation

**Objective:** Confirm the endpoint behavior that determines whether the product can honestly call the displayed value “live.”

**Files:**
- Modify: `README.md` or create `docs/openrouter-notes.md` only if findings need a durable project note.

**Step 1: Inspect the official API references**

Use these sources:

- Activity: <https://openrouter.ai/docs/api/api-reference/analytics/get-user-activity>
- Management keys: <https://openrouter.ai/docs/guides/overview/auth/management-api-keys>
- Usage accounting/generation metadata: <https://openrouter.ai/docs/api/api-reference/generations/get-request-%26-usage-metadata-for-a-generation>

Record the endpoint path, required key type, date format, UTC/completed-day semantics, and spend fields.

**Step 2: Run a credentialed manual probe outside the repository**

With a temporary environment variable containing a management key, run on macOS:

```bash
export OPENROUTER_MANAGEMENT_KEY='...'
curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $OPENROUTER_MANAGEMENT_KEY" \
  "https://openrouter.ai/api/v1/activity?date=$(date -u +%F)"
```

Do not put the key in shell history, a fixture, or a log. Verify whether the current date returns rows, an empty `data` array, or an error.

**Step 3: Make the date policy explicit**

Use the following default unless the probe demonstrates a different current API contract:

- Request the current UTC date.
- Display `UTC` next to the date.
- Display zero only when the API returns a valid empty result for that date.
- Display an unavailable state when the date is not yet published or the request failed.
- Never substitute the previous date without labeling it as a previous date.

**Acceptance:** The plan and README describe a truthful “available UTC-day spend” behavior and identify exact real-time/local-day accounting as a separate product decision.

---

## Task 1: Bootstrap the native macOS package

**Objective:** Create a buildable Swift executable with a menu-bar application bundle configuration.

**Files:**
- Create: `Package.swift`
- Create: `Resources/Info.plist`
- Create: `Sources/MacOSAICostMonitor/App.swift`
- Create: `Sources/MacOSAICostMonitor/AppDelegate.swift`
- Create: `Tests/MacOSAICostMonitorTests/AppSmokeTests.swift` if a small executable-level test is useful.

**Step 1: Add the Swift package manifest**

Configure an executable target named `MacOSAICostMonitor`, macOS 13+, and link the `SwiftUI`, `AppKit`, `Foundation`, and `Security` frameworks where needed. Keep third-party dependencies at zero for the MVP.

**Step 2: Add the agent-app property list**

Set `LSUIElement` to `true`, give the bundle a stable identifier such as `com.example.MacOSAICostMonitor`, and include a human-readable display name and version.

**Step 3: Add the minimal app and delegate shell**

The application delegate should own the lifetime of the status-bar controller. Keep the initial shell free of network calls so the app can launch before later tasks are implemented.

**Step 4: Run the first build**

Run on macOS:

```bash
swift build
swift test
```

Expected: the executable builds and the test command exits successfully. A Linux development machine cannot validate AppKit behavior; macOS is required for this gate.

**Step 5: Commit**

```bash
git add Package.swift Resources Sources Tests
git commit -m "chore: bootstrap macOS menu bar app"
```

---

## Task 2: Define activity models and exact decimal aggregation

**Objective:** Turn OpenRouter activity rows into a deterministic daily summary without coupling the logic to HTTP or SwiftUI.

**Files:**
- Create: `Sources/MacOSAICostMonitor/Models/ActivityItem.swift`
- Create: `Sources/MacOSAICostMonitor/Models/DailyCost.swift`
- Create: `Sources/MacOSAICostMonitor/Services/UsageProvider.swift`
- Create: `Tests/MacOSAICostMonitorTests/ActivityAggregationTests.swift`
- Create: `Tests/MacOSAICostMonitorTests/Fixtures/activity-response.json`

**Step 1: Write the failing aggregation tests**

Cover these behaviors:

```swift
func test_aggregatesUsageTokensAndRequestsAcrossRows() { /* ... */ }
func test_keepsByokEstimateSeparateFromOpenRouterUsage() { /* ... */ }
func test_ignoresRowsForA differentDateWhenAggregatingDefensively() { /* ... */ }
func test_emptyActivityProducesZeroSummaryForRequestedDate() { /* ... */ }
func test_missingOptionalReasoningTokensIsTreatedAsZero() { /* ... */ }
```

Use a fixture with at least two models, two providers, a sub-cent cost, and an optional/missing reasoning-token field. Assert exact `Decimal` values, not formatted strings.

**Step 2: Run the focused tests and verify they fail for the intended reason**

```bash
swift test --filter ActivityAggregationTests
```

Expected: compilation/test failure because the domain types and aggregator do not yet exist.

**Step 3: Implement the smallest domain API**

Use Codable fields matching the documented response:

- `date: String`
- `model: String`
- `modelPermaslug: String?`
- `endpointID: String?`
- `providerName: String`
- `usage: Decimal`
- `byokUsageInference: Decimal?`
- `requests: Int`
- `promptTokens: Int`
- `completionTokens: Int`
- `reasoningTokens: Int?`

Define `DailyCost` with requested date, OpenRouter usage, estimated BYOK usage, request count, token totals, and grouped model/provider rows. Define one pure aggregation function that accepts the requested `YYYY-MM-DD` string and `[ActivityItem]`.

**Step 4: Run the focused tests, then all tests**

```bash
swift test --filter ActivityAggregationTests
swift test
```

Expected: all aggregation assertions pass and no existing tests regress.

**Step 5: Commit**

```bash
git add Sources/MacOSAICostMonitor/Models Sources/MacOSAICostMonitor/Services/UsageProvider.swift Tests
git commit -m "feat: add exact daily usage aggregation"
```

---

## Task 3: Implement the OpenRouter activity client

**Objective:** Fetch one UTC day's activity securely and decode the documented response.

**Files:**
- Create: `Sources/MacOSAICostMonitor/Services/OpenRouterClient.swift`
- Modify: `Sources/MacOSAICostMonitor/Services/UsageProvider.swift`
- Create: `Tests/MacOSAICostMonitorTests/OpenRouterClientTests.swift`
- Modify: `Tests/MacOSAICostMonitorTests/TestDoubles.swift`

**Step 1: Write failing URL-loading tests**

Use an injected `URLSession` backed by a custom `URLProtocol` test double. Verify:

- the request is `GET /api/v1/activity`;
- the query contains exactly `date=YYYY-MM-DD`;
- the `Authorization` header is `Bearer <key>`;
- no key appears in a thrown error or log message;
- a valid `{ "data": [...] }` response decodes;
- 401/403, non-2xx, invalid JSON, and transport failures map to typed errors.

Example test names:

```swift
func test_requestsActivityForUtcDateWithBearerManagementKey() async throws { /* ... */ }
func test_mapsForbiddenResponseToPermissionError() async { /* ... */ }
func test_rejectsMalformedActivityResponse() async { /* ... */ }
```

**Step 2: Run the focused tests and verify the expected red state**

```bash
swift test --filter OpenRouterClientTests
```

Expected: failure because the client and test double are not implemented.

**Step 3: Implement the client**

Inject the base URL and `URLSession` so tests do not use the network. Build the URL with `URLComponents`, set `Accept: application/json` and the Bearer header, enforce a finite request timeout, validate the HTTP status, decode the response envelope, and return `[ActivityItem]`.

Do not log request headers, URLs containing keys, response bodies, prompts, or completions. The client should expose sanitized user-facing error categories such as `unauthorized`, `forbidden`, `rateLimited`, `server`, `network`, and `decoding`.

**Step 4: Run the focused tests and the complete suite**

```bash
swift test --filter OpenRouterClientTests
swift test
```

Expected: all request, decoding, and error tests pass.

**Step 5: Commit**

```bash
git add Sources/MacOSAICostMonitor/Services Tests
git commit -m "feat: fetch OpenRouter activity securely"
```

---

## Task 4: Add Keychain-backed credential storage

**Objective:** Persist the management key securely and provide a testable storage boundary.

**Files:**
- Create: `Sources/MacOSAICostMonitor/Services/KeychainStore.swift`
- Modify: `Sources/MacOSAICostMonitor/State/CostMonitorModel.swift` when it exists.
- Modify: `Tests/MacOSAICostMonitorTests/TestDoubles.swift`
- Create: `Tests/MacOSAICostMonitorTests/KeychainStoreTests.swift` if macOS Keychain tests are available.

**Step 1: Write failing storage contract tests**

Test the protocol rather than hard-coding Security framework calls into view code:

```swift
func test_saveThenReadReturnsTheManagementKey() throws { /* ... */ }
func test_deleteRemovesTheStoredKey() throws { /* ... */ }
func test_missingKeyReturnsNotConfigured() throws { /* ... */ }
```

Use an in-memory fake for ordinary unit tests. Keep an optional macOS integration test for the real Keychain service.

**Step 2: Run tests to verify the red state**

```bash
swift test --filter KeychainStoreTests
```

**Step 3: Implement the Keychain adapter**

Use `kSecClassGenericPassword` with a stable service name and account name. Save/update, read, and delete the value. Return sanitized errors. Do not make the key accessible through `Codable` app state or cache files.

**Step 4: Run tests and inspect the repository**

```bash
swift test
```

Also verify that no fixture, source file, or generated cache contains a real-looking key.

**Step 5: Commit**

```bash
git add Sources/MacOSAICostMonitor/Services Tests
git commit -m "feat: store OpenRouter management key in Keychain"
```

---

## Task 5: Implement non-sensitive usage caching

**Objective:** Preserve the last successful result across temporary network failures without presenting stale data as current.

**Files:**
- Create: `Sources/MacOSAICostMonitor/Services/UsageCache.swift`
- Create: `Tests/MacOSAICostMonitorTests/UsageCacheTests.swift`

**Step 1: Write failing cache tests**

Cover:

- save/load of a successful `DailyCost` and fetch timestamp;
- missing cache;
- corrupt cache treated as a cache miss rather than a crash;
- atomic replacement of the cache file;
- cached data contains no API key;
- a cached result for a different UTC date is not reported as today's result.

**Step 2: Run the focused tests**

```bash
swift test --filter UsageCacheTests
```

Expected: red because the cache is absent.

**Step 3: Implement the file cache**

Store a versioned Codable record under:

```text
~/Library/Application Support/MacOSAICostMonitor/cache.json
```

Create the directory if needed, write to a temporary file, then replace the destination atomically. Keep the cache injectable with a URL so tests use a temporary directory.

**Step 4: Run all tests**

```bash
swift test
```

Expected: cache and previous domain/client tests pass.

**Step 5: Commit**

```bash
git add Sources/MacOSAICostMonitor/Services/UsageCache.swift Tests
git commit -m "feat: cache last successful usage safely"
```

---

## Task 6: Build the refresh/state model

**Objective:** Coordinate credentials, network refreshes, aggregation, caching, stale states, and a bounded polling loop.

**Files:**
- Create: `Sources/MacOSAICostMonitor/State/CostMonitorModel.swift`
- Create: `Sources/MacOSAICostMonitor/State/RefreshScheduler.swift`
- Create: `Tests/MacOSAICostMonitorTests/CostMonitorModelTests.swift`
- Modify: `Tests/MacOSAICostMonitorTests/TestDoubles.swift`

**Step 1: Write failing state tests**

Use a fake provider, fake keychain, fake cache, and controllable clock. Cover:

```swift
func test_missingKeyStartsInSetupState() async { /* ... */ }
func test_successfulRefreshPublishesAggregatedCostAndCachesIt() async { /* ... */ }
func test_emptyCurrentDayPublishesNoDataInsteadOfYesterdayAsToday() async { /* ... */ }
func test_networkFailureKeepsLastValueButMarksItStale() async { /* ... */ }
func test_forbiddenErrorExplainsThatAManagementKeyIsRequired() async { /* ... */ }
func test_overlappingRefreshesAreCoalesced() async { /* ... */ }
```

**Step 2: Run the tests and confirm the expected red state**

```bash
swift test --filter CostMonitorModelTests
```

**Step 3: Implement the state machine**

Make the model `@MainActor` and expose states equivalent to:

```swift
enum MonitorState {
    case notConfigured
    case loading(previous: DailyCost?)
    case loaded(DailyCost, fetchedAt: Date, stale: Bool)
    case noData(date: String, fetchedAt: Date?)
    case failed(message: String, previous: DailyCost?, staleSince: Date?)
}
```

On refresh:

1. Resolve the current UTC date.
2. Read the management key from Keychain.
3. Call the provider once for that date.
4. Aggregate only the requested date.
5. Save a successful result to cache.
6. Publish a loaded/no-data/error state.

Use a five-minute default refresh interval, a manual refresh action, and exponential retry backoff for failures. Cancel the polling task when the app terminates or the model is replaced. Never run two requests concurrently.

**Step 4: Run focused and full tests**

```bash
swift test --filter CostMonitorModelTests
swift test
```

Expected: state transitions, cache behavior, and error handling pass.

**Step 5: Commit**

```bash
git add Sources/MacOSAICostMonitor/State Tests
git commit -m "feat: coordinate usage refresh and stale states"
```

---

## Task 7: Create the menu-bar controller and dashboard popover

**Objective:** Make the cost visible at a glance and provide useful detail on click.

**Files:**
- Create: `Sources/MacOSAICostMonitor/UI/StatusBarController.swift`
- Create: `Sources/MacOSAICostMonitor/UI/DashboardView.swift`
- Modify: `Sources/MacOSAICostMonitor/AppDelegate.swift`
- Modify: `Sources/MacOSAICostMonitor/App.swift`

**Step 1: Add view/model presentation tests where practical**

At minimum, test cost-formatting and state-to-label mapping in pure Swift helpers before wiring the AppKit objects. UI-only layout behavior can be covered by a macOS manual checklist.

**Step 2: Implement the status item**

Create an `NSStatusItem` with variable length and a button action. Update its title from the model state:

- loaded: formatted OpenRouter usage;
- no data: `—`;
- loading: previous value or `…`;
- failed with previous value: previous value, with a stale indicator in the popover.

Set an accessibility label such as `OpenRouter cost for today: $0.42`.

**Step 3: Implement the SwiftUI popover**

Use an `NSPopover` containing a SwiftUI `DashboardView`. Include:

- date and `UTC` label;
- large total cost;
- requests and token totals;
- model/provider rows sorted by descending cost;
- last update time;
- a `Refresh now` button;
- a clear explanation for no data, stale data, permission errors, or missing credentials;
- `Settings` and `Quit` actions.

The popover must not expose the management key after it has been saved.

**Step 4: Run the app manually on macOS**

```bash
swift run
```

Expected: the process launches without a Dock icon, a status item is visible, clicking it opens the popover, and quitting terminates cleanly. Network setup can remain unavailable until Task 8 is complete.

**Step 5: Commit**

```bash
git add Sources/MacOSAICostMonitor
git commit -m "feat: show cost in macOS menu bar"
```

---

## Task 8: Add setup, settings, formatting, and user-facing error states

**Objective:** Make the MVP usable by a person who has not configured the app yet.

**Files:**
- Create: `Sources/MacOSAICostMonitor/UI/SettingsView.swift`
- Create: `Sources/MacOSAICostMonitor/UI/CostFormatStyle.swift`
- Modify: `Sources/MacOSAICostMonitor/UI/DashboardView.swift`
- Modify: `Sources/MacOSAICostMonitor/State/CostMonitorModel.swift`
- Modify: `README.md`

**Step 1: Write failing formatting tests**

Test stable rules for:

- zero dollars;
- values below one cent;
- normal dollar values;
- large values;
- token counts with thousands separators;
- stale and unavailable status text.

**Step 2: Implement formatting and setup UI**

Use a `SecureField` for the management key, a save button, and a short explanation that activity access requires a management key rather than a normal inference key. On save, write to Keychain and trigger a refresh; clear the input after a successful save.

Use `Decimal` for calculations and `NumberFormatter`/`FormatStyle` only at the presentation boundary. The main total should remain readable in a narrow status item; details may show more precision.

**Step 3: Implement sanitized error copy**

Map technical errors to actionable messages:

- missing key: `Add an OpenRouter management key in Settings.`
- 401: `The key was rejected. Check that it is still active.`
- 403: `This endpoint requires an OpenRouter management key with activity access.`
- rate limit: `OpenRouter rate-limited the refresh. Retrying later.`
- network: `OpenRouter could not be reached. Showing the last known value.`
- no data: `OpenRouter has not published activity for this UTC day yet.`

Do not display raw response bodies or include credentials in diagnostics.

**Step 4: Run tests and perform the setup flow manually**

```bash
swift test
swift run
```

Manual checks:

- entering a key persists it after relaunch;
- the key field is not prefilled with the raw key;
- invalid credentials produce a useful error;
- successful data updates both the popover and menu-bar title;
- closing/reopening the popover does not start duplicate refresh loops.

**Step 5: Commit**

```bash
git add Sources/MacOSAICostMonitor README.md Tests
git commit -m "feat: add secure setup and status messaging"
```

---

## Task 9: Package a distributable `.app`

**Objective:** Produce a repeatable local release artifact instead of requiring `swift run`.

**Files:**
- Create: `Scripts/build-app.sh`
- Modify: `Resources/Info.plist`
- Modify: `README.md`
- Optional: `Resources/AppIcon.icns`

**Step 1: Write the packaging script**

The script should:

1. run `swift build -c release`;
2. create `dist/MacOSAICostMonitor.app/Contents/MacOS` and `Contents/Resources`;
3. copy the release executable and `Info.plist`;
4. copy an icon if present;
5. optionally ad-hoc sign the bundle for local testing;
6. print the absolute artifact path.

Fail on any command error and never copy credentials or cache files into the bundle.

**Step 2: Build and inspect the bundle**

Run on macOS:

```bash
bash Scripts/build-app.sh
plutil -p dist/MacOSAICostMonitor.app/Contents/Info.plist
codesign --verify --deep --strict dist/MacOSAICostMonitor.app
```

Expected: all commands exit zero and `LSUIElement` is true.

**Step 3: Launch the packaged app**

```bash
open dist/MacOSAICostMonitor.app
```

Verify that the packaged app behaves the same as `swift run` and terminates cleanly.

**Step 4: Commit**

```bash
git add Scripts Resources README.md
git commit -m "build: package menu bar app bundle"
```

---

## Task 10: Complete verification and documentation

**Objective:** Verify the requirements end-to-end and document installation, permissions, limitations, and troubleshooting.

**Files:**
- Modify: `README.md`
- Optional: `docs/troubleshooting.md`

**Step 1: Run the complete automated suite**

```bash
swift test
```

Expected: zero test failures and no unhandled concurrency warnings introduced by the project.

**Step 2: Run a release build and bundle checks**

```bash
bash Scripts/build-app.sh
plutil -p dist/MacOSAICostMonitor.app/Contents/Info.plist
codesign --verify --deep --strict dist/MacOSAICostMonitor.app
```

**Step 3: Execute the credentialed integration check**

With a real management key supplied interactively or through a protected environment variable:

- fetch current UTC activity;
- verify the displayed total matches the sum of the API `usage` rows;
- verify a second refresh does not double-count rows;
- verify a 403 is explained as a key-permission issue;
- verify no prompt/completion or API key is written to logs/cache.

Remove the key from the environment after testing.

**Step 4: Perform the manual acceptance checklist**

- [ ] App appears only in the menu bar.
- [ ] Menu-bar value is readable at normal and dark-mode appearances.
- [ ] Popover opens and closes reliably.
- [ ] Empty-day, loading, stale, offline, unauthorized, and forbidden states are distinguishable.
- [ ] The date is explicitly marked UTC.
- [ ] The app does not silently substitute yesterday's data.
- [ ] Refreshes occur no more often than the configured interval.
- [ ] Manual refresh works.
- [ ] Keychain setup survives relaunch.
- [ ] Cache survives relaunch but contains no credential.
- [ ] Quit works from the popover.
- [ ] The packaged `.app` launches independently of the build directory.

**Step 5: Document setup and limitations**

`README.md` should include:

- supported macOS version;
- build/run/package commands;
- how to create an OpenRouter management key with activity read access;
- where the key is stored;
- what “OpenRouter usage” and estimated BYOK mean;
- the 30 completed UTC-day limitation;
- the fact that exact live local-day totals require a future instrumentation approach;
- troubleshooting for 401/403, rate limits, empty current-day data, and network failures.

**Step 6: Commit**

```bash
git add README.md docs Scripts Resources Sources Tests
git commit -m "docs: document setup and usage limitations"
```

---

## Risks, Tradeoffs, and Follow-up Decisions

1. **Current-day availability:** The official activity API may not return in-progress activity. The UI must prefer an honest unavailable/stale state over a misleading number. If the product absolutely requires live same-day totals, investigate a local OpenRouter request wrapper or an opt-in SDK integration.
2. **UTC versus local day:** OpenRouter activity is grouped by UTC date. A local-day total cannot be reconstructed accurately from one UTC bucket. Keep UTC explicit in the MVP; add local-day support only if a future API provides event-level timestamps.
3. **Management-key permissions:** A standard inference key may work for model requests but is insufficient for account activity. Setup and error copy must make this distinction clear.
4. **BYOK accounting:** `usage` and `byok_usage_inference` have different billing semantics. Keep them separate until a product decision defines whether the headline should mean OpenRouter credits, estimated total spend, or both.
5. **Polling and rate limits:** Five-minute polling is intentionally conservative. Add configurable intervals only after observing the endpoint's rate-limit behavior.
6. **Multiple workspaces/organization members:** The initial display should represent the activity returned for the authenticated account. Workspace/member filters can be added after the basic account-level flow is stable.
7. **Distribution:** Ad-hoc signing is suitable for local testing only. Developer ID signing, notarization, auto-update, and App Store sandbox entitlements are separate release work.

## Definition of Done

The MVP is ready for user testing only when:

- all automated tests pass on macOS;
- a release `.app` builds and passes bundle verification;
- a real management-key integration fetches and displays a verified total;
- credentials are Keychain-only and absent from logs/cache;
- the UI clearly distinguishes current available data, no data, stale data, and errors;
- the README documents the completed-UTC-day limitation and does not promise unsupported real-time local-day accounting.

## Recommended Execution Order

Execute Tasks 0–6 sequentially because each later layer depends on the preceding contract. Tasks 7 and 8 can be implemented together after the state model is stable. Task 9 depends on the final app entry point, and Task 10 is the final verification gate.

For implementation, use strict red-green-refactor TDD for the domain, client, cache, and state tasks, followed by the `verification-before-completion` skill before claiming the app is buildable or working.
