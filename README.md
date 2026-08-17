# AI Cost Monitor for macOS

A native macOS menu-bar application for monitoring AI service spend, starting with OpenRouter.

## MVP status

The first implementation targets OpenRouter account activity and displays the spend reported for the requested **UTC date**. The menu-bar value is account-level OpenRouter usage, not a locally inferred estimate.

### OpenRouter limitation

The OpenRouter activity API is:

```text
GET https://openrouter.ai/api/v1/activity?date=YYYY-MM-DD
```

It requires an OpenRouter **management API key** with activity access and exposes the last 30 completed UTC days. The application requests the latest completed UTC day rather than the in-progress day, because OpenRouter may reject or omit current-day activity. Exact real-time local-day totals require request instrumentation or a future event-level API and are not claimed by this MVP.

The headline total sums each activity row's `usage` field. `byok_usage_inference` is retained as a separate estimated BYOK amount and is not added to the headline total.

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
- **No completed-day data:** OpenRouter has not published activity for the requested completed UTC day yet.

## Development note

The repository can be edited on Linux, but AppKit, SwiftUI, Keychain Services, `swift test`, and `.app` verification must be run on macOS. The CI/release checklist should run `swift test`, `Scripts/build-app.sh`, `plutil`, and `codesign --verify --deep --strict` on a macOS runner.
