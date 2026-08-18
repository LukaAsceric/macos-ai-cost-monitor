# Reddit-Beitrag: AI Cost Monitor for macOS

Fertiger Post (Englisch – die Ziel-Subreddits sind englischsprachig). Struktur:

1. Titel-Varianten pro Subreddit
2. Haupt-Post (Textbody) – für r/macapps, r/SideProject, r/indiehackers, r/opensource
3. Kompakt-/Abwandlungen für r/LLMDevs, r/openrouter (Megathread), r/AI_Agents (Weekly Thread), r/AlphaAndBetausers

Fakten-Grundlage: README + GitHub (Repo `LukaAsceric/macos-ai-cost-monitor`, MIT, Release v0.3.0 mit DMG/ZIP). Vor dem Posten: **Screenshot des Menu-Bar-Popovers** als erstes Bild anhängen (siehe Platzhalter).

---

## 1. Titel (Variante je Subreddit auswählen)

- **r/SideProject** (Format laut Sidebar: `[Project name] - [Short description]`):
  `AI Cost Monitor for macOS - free open-source menu bar app that tracks your OpenRouter AI spend`
- **r/macapps**:
  `I built a free, open-source macOS menu bar app to track AI API spending (OpenRouter)`
- **r/LLMDevs**:
  `Open-source (MIT) macOS menu bar app for tracking OpenRouter API costs with budget alerts`
- **r/indiehackers** (Flair: „Self Promotion"):
  `Show: I built a free open-source macOS app that puts your OpenRouter AI spend in the menu bar`
- **r/opensource**:
  `I open-sourced my macOS menu bar app for monitoring AI API spend (MIT)`
- **r/openrouter** – als **Kommentar im monatlichen Megathread**:
  `AI Cost Monitor - native macOS menu bar app for tracking OpenRouter spend (open source, free)`
- **r/AI_Agents** – **Weekly Project Display Thread**:
  `AI Cost Monitor - open-source macOS menu bar app for agent/API spend tracking on OpenRouter`
- **r/AlphaAndBetausers** (Pflicht-Tag):
  `[macOS, Beta] AI Cost Monitor - track your OpenRouter AI spend from the menu bar`
- **r/MacOS** (nur Samstag UTC):
  `Showcase: free open-source macOS app to monitor OpenRouter AI costs`

---

## 2. Haupt-Post (Textbody)

```markdown
I kept opening the OpenRouter dashboard in my browser just to see what my API usage was costing me. So I built a native macOS app that puts the answer right in the menu bar: **AI Cost Monitor**.

![AI Cost Monitor - Menu bar popover with spend sparkline](<HIER SCREENSHOT EINFÜGEN>)

**What it does**
- Shows your current spend in the menu bar with a sparkline; the popover adds optional token, request, provider and model details
- Report ranges from "last 15 minutes" to "last year", calendar ranges (today, this week, this month, ...), custom From/To, and the latest completed day / last 30 days
- Model-level breakdown, optionally grouped across providers (OpenRouter routes many providers to the same model)
- Local budget threshold with a macOS notification before you blow the budget
- Timezone control, decimal precision, raw HTTP capture and sanitized log export for debugging

**Privacy & security**
- Your OpenRouter management key lives in the macOS Keychain - never in settings, logs, or the usage cache
- No account, no telemetry: nothing leaves your Mac except the analytics requests you trigger

**Status & roadmap**
- Working today: OpenRouter (via their Analytics API) on macOS 13 Ventura+
- Next up: more providers (OpenAI, Anthropic, ...) and notarized release builds
- Auto-updates via Sparkle with EdDSA-signed appcasts; updates are user-approved

**Install**
Free and MIT-licensed. Download the DMG from GitHub Releases and drag it to Applications - first launch is right-click -> Open (ad-hoc signed for now, notarization pending). SHA256SUMS.txt is provided for verification.

- Repo: https://github.com/LukaAsceric/macos-ai-cost-monitor
- Releases: https://github.com/LukaAsceric/macos-ai-cost-monitor/releases

Disclosure: I'm the developer. This is a young project, so feedback and bug reports are genuinely appreciated - the roadmap is driven by what users actually need.
```

---

## 3. Subreddit-Abwandlungen

### r/LLMDevs (sachlich, Dev-Sprache, keine Werbesprache)
Regelkonform, weil MIT/FOSS und keine bezahlte Version existiert. Anpassungen am Haupt-Post:
- Titel: `Open-source (MIT) macOS menu bar app for tracking OpenRouter API costs with budget alerts`
- Ersten Absatz ersetzen durch:
  `I wanted a one-glance overview of OpenRouter API spend per model without keeping the dashboard open in a browser, so I built a small native macOS menu bar app (SwiftUI/AppKit, MIT).`
- „Budget threshold"-Zeile betonen; Werbungssprache („free", Emojis) streichen.

### r/openrouter (nur Kommentar im monatlichen Megathread)
Kein eigener Post – die Regeln verbieten Eigenprojekt-Links außerhalb des Megathreads (Wiederholung = Ban). Kommentar-Vorschlag:

```markdown
I built a native macOS menu bar app for tracking OpenRouter spend: AI Cost Monitor.

- Menu bar spend + sparkline, token/request/model details in a popover
- Ranges from 15 minutes to 1 year, calendar ranges, custom From/To
- Per-model breakdown (groupable across providers), budget threshold with macOS notification
- Management key stored in the macOS Keychain; no telemetry
- MIT, free, Sparkle auto-update: https://github.com/LukaAsceric/macos-ai-cost-monitor

Happy to hear what's missing - providers beyond OpenRouter are on the roadmap.
```

### r/AI_Agents (Weekly Project Display Thread)
Gleicher Kommentar-Stil wie r/openrouter, plus Satz zur Agent-Relevanz:
`Useful if you run agent loops or long batch jobs on OpenRouter - the budget alert fires before a runaway session gets expensive.`

### r/AlphaAndBetausers (Tag im Titel; Link zum testbaren Produkt ist Pflicht)
- Titel: `[macOS, Beta] AI Cost Monitor - track your OpenRouter AI spend from the menu bar`
- Body: Haupt-Post, aber Abschnitt „Install" ersetzen durch expliziten Beta-Call-to-Action:
  `The app is in public beta (v0.3.0). Testers needed, especially for: budget alerts, long-running report ranges, and Keychain behavior on fresh installs. DMG: https://github.com/LukaAsceric/macos-ai-cost-monitor/releases - requirements: macOS 13+, an OpenRouter management key with analytics access.`

### r/MacOS (nur samstags UTC; Risiko beim jungen Repo)
Haupt-Post, Titel aus der Liste. Erwartung managen: Bei „not reputable/established" kann der Post entfernt werden.

---

## Checkliste vor dem Absenden

- [ ] Screenshot eingefügt (Platzhalter ersetzen)
- [ ] Passender Titel für das jeweilige Subreddit gewählt
- [ ] Disclosure „I'm the developer" enthalten (Pflicht in r/macapps)
- [ ] r/indiehackers: Flair „Self Promotion" gesetzt
- [ ] r/AlphaAndBetausers: Tag `[macOS, Beta]` im Titel, Link vorhanden
- [ ] r/MacOS: nur samstags (UTC) posten
- [ ] r/openrouter/r/AI_Agents: im Megathread, nicht als eigener Post
- [ ] Zeitslots: Di–Do, ~14:00–17:00 MESZ (US-Morgen)