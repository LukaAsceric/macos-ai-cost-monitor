# AI Cost Monitor for macOS

A native macOS menu-bar application for monitoring AI service spend, starting with OpenRouter.

## MVP status

The first implementation targets OpenRouter account activity and displays the spend reported for the newest **completed UTC date** currently returned by OpenRouter. The menu-bar value is account-level OpenRouter usage, not a locally inferred estimate.

### OpenRouter limitation

The OpenRouter activity API is:

```text
GET https://openrouter.ai/api/v1/activity?date=YYYY-MM-DD
```

It requires an OpenRouter **management API key** with activity access and exposes the last 30 completed UTC days. The application requests that recent window without a date filter, then selects the newest date actually returned. Exact real-time local-day totals require request instrumentation or a future event-level API and are not claimed by this MVP.

The headline total sums each activity row's `usage` field. `byok_usage_inference` is retained as a separate estimated BYOK amount and is not added to the headline total.

## Reporting settings

The Settings panel supports:

- **Latest available day**: show the newest completed UTC day returned by OpenRouter.
- **Last 30 completed days**: aggregate the full activity window returned by OpenRouter.
- **Refresh interval**: 1, 5, 15, or 30 minutes.
- **Cost decimals**: choose 2–8 displayed fractional digits; the default is 6 so small costs remain visible.
- **Include estimated BYOK in headline**: optionally add OpenRouter's estimated BYOK amount to the menu-bar headline. It remains separately labeled in the details.

The service's reporting dates are UTC because that is the API's accounting basis. A local timezone selector would change presentation labels but cannot convert the API's completed UTC-day buckets into exact local-day totals.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools or Xcode
- An OpenRouter management API key with activity read access

## Build and run

```bash
swift build
swift test
swift run
```

To create a local application bundle:

```bash
bash Scripts/build-app.sh
open dist/MacOSAICostMonitor.app
```

Use the signed `.app` bundle for normal operation. `swift run` launches a development executable whose code identity can change after rebuilds; macOS may consequently ask for Keychain authorization again. For a stable local identity, build with an explicit signing identity:

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" bash Scripts/build-app.sh
open dist/MacOSAICostMonitor.app
```

The app reads the management key once per launch and keeps it only in memory for subsequent refreshes. Keychain reads are non-interactive; if macOS requires authorization for an existing item, the app reports that requirement instead of triggering a password prompt from every refresh.

The key is stored in the macOS Keychain. It is not written to UserDefaults, the usage cache, logs, or the application bundle.

## Setup

1. Create a management key in OpenRouter Settings → Management Keys.
2. Grant the key activity read access.
3. Launch the application.
4. Open Settings from the menu-bar popover and paste the key into the secure field.
5. Save, then use **Refresh now**.

A regular inference key is not sufficient for the activity endpoint. If the requested completed UTC day has no published data, the application reports that state and keeps the date labeled UTC.

## Troubleshooting

- **401:** the key was rejected or revoked; create/check the key again.
- **403:** the key lacks management/activity permission.
- **429:** OpenRouter rate-limited the request; the app will retry on its normal schedule.
- **Network failure:** the last successful value may remain visible but is marked stale.
- **Repeated Keychain prompts:** do not use `swift run` for normal operation. Build and launch `dist/MacOSAICostMonitor.app` so macOS sees a stable signed application identity. The app reads the key once per launch and uses non-interactive Keychain reads thereafter.
- If an older `swift run` build owns the existing item, remove only the app's old item in Keychain Access (service `com.example.MacOSAICostMonitor`, account `openrouter-management-key`), then save the key again from the signed `.app`.
- **No completed-day data:** OpenRouter has not published activity for the requested completed UTC day yet.

## Development note

The repository can be edited on Linux, but AppKit, SwiftUI, Keychain Services, `swift test`, and `.app` verification must be run on macOS. The CI/release checklist should run `swift test`, `Scripts/build-app.sh`, `plutil`, and `codesign --verify --deep --strict` on a macOS runner.
