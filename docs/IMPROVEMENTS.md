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
- [x] **Chart-Geometrie (SpendChartView)** — reine, testbare `SpendChartLayout`-
      Helfer: Single-Point wird horizontal zentriert (statt links angepinnt),
      Y-Position wird geklammert (Ausreißer/negative Werte verlassen die Bounds
      nie), Flächen-Gradient unter der Kurve, 7 Unit-Tests für alle Randfälle.
- [x] **Display-only-Präferenzen vom Refresh entkoppelt** — `applyPreferenceChanges`
      triggert bei dem reinen Anzeige-Toggles (Gruppierung, Provider-Namen, Voll-Liste,
      Token-/Request-Details) keinen Netzwerk-Request mehr.
- [x] **`actions/upload-artifact@v5`** — von v4 auf v5 angehoben. Die Node-20-Laufzeitwarnung
      besteht jedoch weiterhin (v5 wird ebenso unter Node 24 erzwungen); rein kosmetische
      Warnung ohne Funktionsfehler, bei Gelegenheit erneut prüfen.
- [x] **Sparkle-Archiv-Layout-Pitfall dokumentiert** — Skill `macos-release-updates`.

## Bereits vorhanden (nur verifiziert, kein Handlungsbedarf)

- [x] **Cache-Versionsmarker** — `CachedUsage` trägt bereits ein `version`-Feld;
      `UsageCache.load()` verwirft jede Datei mit `version != 1` (Test
      `test_rejectsUnsupportedCacheVersion` vorhanden).

## UX / Anzeige

- [ ] **Menüleisten-Tooltip mit stale/budget-Anreicherung** — bereits teils vorhanden;
      Konsistenz für alle States (`.noData` mit previous).
- [x] **`—` statt `…` bei initialem Loading ohne Cache** — Menüleiste zeigt im ersten
      Lade-Zyklus ohne previous-Wert jetzt `—` (konsistent zu den übrigen Zuständen).
- [x] **Datum im Dashboard lesbar formatiert + UTC-Badge** — `readableDayLabel` formatiert
      `yyyy-MM-dd` bei UTC (Bucket-verschiebungsfrei: keine lokale Zeitumstellung, die den
      UTC-Tages-Bucket fehldarstellen würde); expliziter „UTC"-Badge im Header.

## Zuverlässigkeit / Korrektheit

- [ ] **DoS-Guard für lange Modell-/Provider-Strings** — extrem lange Zeichenketten
      bei `lineLimit`/Importen; kein harter Fehlerzustand.

## Nicht priorisiert / bewusst offen

- Erweiterte Provider-Integrationen (OpenAI, Anthropic, …) — bewusst „Coming soon".
- OAuth-Login statt Management-Key — bewusst verworfen (Analytics braucht Management-Key).
- App-Store-Distribution — bewusst außerhalb Scope.