# AI Cost Monitor — Verbesserungsliste

Geführte, priorisierte Liste von Verbesserungen/Ergänzungen. Status wird laufend
aktualisiert. Kodierte Änderungen laufen über CI (swift test auf macOS-Runner);
lokale Swift-Ausführung ist auf dem Linux-DEV-Host nicht möglich.

Legende: `[ ]` offen · `[x]` umgesetzt · `[skipped]` bewusst verworfen.

## Abgeschlossen

- [x] **Modellliste ohne Provider-Split** — Option `groupModelsAcrossProviders`
      (Reporting-Settings-Toggle) führt Breakdown-Zeilen mit gleichem Modell über
      Provider hinweg zusammen (usage/requests/tokens summiert, Provider zu
      sortierter deduplizierter Liste). Reiner Anzeige-Eingriff; Cache-Struktur
      unverändert.

## UX / Anzeige

- [ ] **Chart-Verbesserung (SpendChartView)** — Fläche unter der Kurve (Gradient),
      besserer Single-Point-Fall, dezente Minimal-/Maximal-Marker.
- [ ] **Menüleisten-Tooltip mit stale/budget-Anreicherung** — bereits teils vorhanden;
      Konsistenz für alle States (`.noData` mit previous).
- [ ] **`—` statt `…` bei initialem Loading ohne Cache** — Menüleiste zeigt im ersten
      Lade-Zyklus ohne previous-Wert aktuell `…`; optional dezenteres Verhalten.
- [ ] **Datum im Dashboard als lokal formatierte Angabe + UTC-Badge** — UTC-Primär,
      dafür klare Lesbarkeit.

## Zuverlässigkeit / Korrektheit

- [ ] **Display-only-Präferenzen von Refresh entkoppeln** — `applyPreferenceChanges`
      triggert derzeit bei jedem reinen Anzeige-Toggle (Gruppierung, Provider-Namen,
      Voll-Liste) einen Netzwerk-Refresh. Aufteilen in „Daten" vs. „Anzeige"-Änderungen,
      um unnötige Requests zu vermeiden.
  _(umgesetzt: daten-relevante Präferenzen behalten Refresh; Anzeige-Toggles nicht mehr)_
- [ ] **DoS-Guard für gruppierte Modellnamen** — extrem lange Modell-/Provider-Zeichenketten
      bei `lineLimit`/Importen; kein harter Fehlerzustand.
- [ ] **Cache-Migration/Versionsmarker** — CachedUsage auf expliziten Format-Versions-Marker
      prüfen (Datei bereits versioniert prüfen).

## Automatisierung / CI

- [x] **`actions/upload-artifact@v4` Node-20-Deprecation** — bei nächster Gelegenheit
      Major-Bump (v4 → v5) im Release-Workflow gegen die Laufzeit-Warnung.
- [x] **Sparkle-Archiv-Layout-Pitfall dokumentiert** — Skill `macos-release-updates`.

## Nicht priorisiert / bewusst offen

- Erweiterte Provider-Integrationen (OpenAI, Anthropic, …) — bewusst „Coming soon".
- OAuth-Login statt Management-Key — bewusst verworfen (Analytics braucht Management-Key).
- App-Store-Distribution — bewusst außerhalb Scope.