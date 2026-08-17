# Provider, Time Range, and Raw HTTP Diagnostics Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Provider settings section, a screenshot-inspired time-range picker with honest disabled states for unsupported ranges, and opt-in raw HTTP response diagnostics.

**Architecture:** Keep OpenRouter as the only enabled provider behind the existing `UsageProvider` abstraction. Expand persisted reporting preferences with provider selection, time-range selection, and raw-response capture. The OpenRouter client receives a diagnostic log store and captures response metadata/body only when explicitly enabled; authorization headers and request secrets are never logged. Unsupported time ranges remain visible but disabled because the current activity API exposes completed UTC-day buckets, not minute/hour/calendar-local windows.

**Verification:** On macOS run `swift build`, `swift test`, and the signed app. On Linux run static Swift checks, secret scans, plist validation, and shell checks.

## Tasks

1. **Preferences and provider catalog**
   - Extend `ReportingPreferences` with `ProviderOption`, `ReportTimeRange`, and `captureRawHTTPResponses`.
   - Persist values in `UserDefaults` with safe defaults: OpenRouter, latest available completed UTC day, raw capture off.
   - Add known providers as disabled catalog entries: OpenAI, Anthropic, Google AI, Mistral, Groq, xAI, Together AI, Fireworks, DeepSeek, Cohere, and Perplexity.
   - Test persistence, defaults, and supported/unsupported flags.

2. **Provider section**
   - Rename the sidebar item from OpenRouter to Provider.
   - Show a provider list with OpenRouter enabled and all unimplemented providers disabled/greyed out with “Coming soon”.
   - Keep the management-key form visible for the selected OpenRouter provider.

3. **Time-range section**
   - Add grouped choices matching the supplied screenshot: relative ranges, calendar ranges, and custom range.
   - Keep unsupported minute/hour/local-calendar/custom choices disabled.
   - Provide enabled choices for “Latest available completed UTC day” and “Last 30 completed UTC days”.
   - Make the report model switch only over enabled values and label the UTC/completed-day limitation.

4. **Raw HTTP diagnostics**
   - Add an opt-in Console toggle: “Capture raw HTTP responses”.
   - Extend the provider/client diagnostic seam so OpenRouter receives the flag.
   - Log method, endpoint path, status, response byte count, and raw response body only when enabled.
   - Never log Authorization headers, management keys, raw request URLs with secrets, or response bodies by default.
   - Display raw entries distinctly in the Console and apply redaction again on Copy.
   - Add tests for disabled capture, enabled capture, and no authorization-header leakage.

5. **Verification and publish**
   - Run macOS build/tests if available; otherwise run all static checks.
   - Update README with disabled range/provider behavior and raw-response privacy warning.
   - Commit and push to `main`.

## Explicit limitations

- The current OpenRouter activity endpoint does not provide exact past-15-minutes, hourly, local-calendar-day, or arbitrary custom ranges.
- Enabling raw response capture may expose account activity details in the in-memory console; it is off by default, capped by the existing log capacity, and not persisted.
- No additional provider integration is implemented in this change.

## Suggested commit

`feat: add provider and time range diagnostics`

## Completion checklist

- [ ] Provider renamed and catalog shown
- [ ] Non-implemented providers disabled
- [ ] Screenshot-inspired time range groups shown
- [ ] Unsupported ranges disabled
- [ ] Raw response capture opt-in
- [ ] Authorization headers never logged
- [ ] Tests and static checks pass
- [ ] README updated
- [ ] Commit pushed

## Plan complete

Plan saved to `docs/plans/2026-08-17-provider-time-range-raw-http.md`. Execute task-by-task in this session with the existing TDD and verification workflows.