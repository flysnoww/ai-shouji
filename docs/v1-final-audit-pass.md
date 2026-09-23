# V1 final functional and interaction pass

Baseline: `main@31db878`. Keep the four modules, owner scoped records, existing data format, skin schema, and current Core save boundary.

## Work and checks

1. Unify supported currency aliases in Core. Parse every transaction amount, preserve true-total precedence, and verify alias searches against canonical amount items.
2. Keep one selected Speech recognizer at runtime. Add explicit English selection; route both transcripts through the existing parser. Stabilize English interpretation with a frozen, honest benchmark.
3. Add a small SwiftUI card tilt and highlight that yields to navigation and Reduce Motion.
4. Present record detail in a native resizable sheet from lists and Search. Keep Search state in place and verify that viewing never saves.
5. Audit Core and UI paths for confirmed safety, state, localization, and performance defects. Fix only evidenced issues.
6. Run local checks where available, macOS CI, then build and verify an unsigned internal IPA.

## Change log

- 2026-09-22: Baseline inspected. `amountItems` returns after the first symbol amount; currency query parsing uses a separate alias list. Speech is fixed to zh-CN. Detail is a navigation destination. No data migration planned.
- 2026-09-22: Shared currency aliases and mixed-amount extraction; canonical currency search and filtered totals. Added an explicit 100-utterance English parser benchmark and conservative multi-intent split. English Speech is opt-in and still uses one recognizer.
- 2026-09-22: Home card touch tilt/highlight respects Reduce Motion. Search/list present Detail with a native sheet. Viewing a missing external reminder now reports status without writing the record; reminder linking is guarded against duplicate concurrent requests.

## Deferred verification

- Simulator CI cannot prove microphone capture, recognizer locale availability, sheet feel, or tap/scroll ergonomics on an iPhone. These remain device confirmation items.
- The package workflow produces an unsigned IPA. Its existence does not prove installability without external signing.
