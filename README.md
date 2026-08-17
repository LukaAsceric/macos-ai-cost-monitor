# AI Cost Monitor for macOS

A native macOS menu-bar application for monitoring AI service spend, starting with OpenRouter.

## Current status

The app queries OpenRouter **Analytics**:

```text
POST https://openrouter.ai/api/v1/analytics/query
```

That endpoint accepts an explicit `time_range` and `granularity` (`minute`, `hour`, `day`, `week`, `month`). The browser Activity UI uses the same contract. A management key is required. Regular inference keys and OpenRouter OAuth PKCE keys return 403 here.

The older Activity endpoint (`GET /api/v1/activity`) remains available as a fallback client method, but the live dashboard uses Analytics.

## Reporting

All screenshot-style ranges are enabled:

- Relative: Past 15/30 minutes, 1/3/24/48 hours, 1 week, 1 month, 1 year
- Calendar: Today, Yesterday, This/Previous Week, This/Previous Month, This/Previous Year
- Custom range with From/To pickers
- Latest available completed UTC day and last 30 days

Calendar ranges use the selected display timezone. The example payload from the OpenRouter UI:

```json
{
  "metrics": ["total_usage"],
  "dimensions": ["model"],
  "granularity": "day",
  "time_range": {
    "start": "2026-08-16T22:00:00.000Z",
    "end": "2026-08-17T20:59:02.061Z"
  }
}
```

is the same shape this app sends. `Today` in GMT+2 therefore starts at `22:00Z` the previous UTC day.

## Settings

The retained settings window has:

- **General / Overview** — live connection state, management-key status, current report, last refresh, cache/console activity, and quick actions
- **Provider** — OpenRouter is enabled; other providers remain listed as coming soon
- **Reporting** — ranges, timezone, decimals, detail toggles, raw HTTP capture
- **Alerts** — local budget threshold and optional macOS notification
- **Release** — what local signing can and cannot do
- **Console** — filter, copy, clear, sanitized log export

General is intentionally an operational overview rather than a second settings form. Configuration lives in Provider, Reporting, and Alerts; General tells you what the monitor is doing right now and provides shortcuts to those areas.

The window can only be closed. It cannot be minimized or maximized.

## Product features

- Compact menu-bar popover with spend, optional token/request/provider details, and a sparkline
- Local budget threshold with optional notification
- Sanitized console export to Application Support
- Signed local `.app` via `Scripts/build-app.sh`

Not included, and documented in Settings → Release:

- Auto-update
- Developer ID notarization
- Mac App Store packaging
- OAuth login — OpenRouter OAuth mints an inference key, not a management key

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools or Xcode
- An OpenRouter management API key with analytics/activity access

## Install a release

Download the latest **DMG** from the repository's [Releases](https://github.com/LukaAsceric/macos-ai-cost-monitor/releases) page, open it, and drag **MacOSAICostMonitor.app** to Applications.

This public preview is ad-hoc signed and not notarized. On first launch, Control-click the app and choose **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**. Verify the downloaded DMG or ZIP with `SHA256SUMS.txt` when desired.

## Build and run

```bash
swift build
swift test
bash Scripts/build-app.sh
open dist/MacOSAICostMonitor.app
```

Use the signed `.app` for normal operation. `swift run` can change the development executable identity and cause repeated Keychain prompts.

```bash
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" bash Scripts/build-app.sh
```

The key is stored in the macOS Keychain. It is not written to UserDefaults, the usage cache, logs, or the application bundle.

## Setup

1. Create a management key in OpenRouter Settings → Management Keys.
2. Grant analytics/activity read access.
3. Launch the signed app.
4. Open Settings and paste the key.
5. Choose a report range and use **Refresh now**.

## Troubleshooting

- **401:** the key was rejected or revoked
- **403:** the key is not a management key or lacks analytics access
- **429:** OpenRouter rate-limited the request
- **Repeated Keychain prompts:** launch `dist/MacOSAICostMonitor.app`, not `swift run`

## Development note

The repository can be edited on Linux, but AppKit, SwiftUI, Keychain, `swift test`, and `.app` verification must be run on macOS.
