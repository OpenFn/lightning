---
paths:
  - "lib/lightning/adaptors.ex"
  - "lib/lightning/adaptors/**"
  - "lib/lightning_web/controllers/adaptor_icon_controller.ex"
  - "lib/mix/tasks/lightning.adaptors.refresh.ex"
  - "lib/mix/tasks/lightning.adaptors.import.ex"
  - "lib/mix/tasks/lightning.adaptors.dump.ex"
  - "lib/mix/tasks/lightning.adaptors.snapshot.ex"
  - "test/lightning/adaptors_test.exs"
  - "test/lightning/adaptors/**"
  - "test/mix/tasks/lightning.adaptors.*.exs"
  - "assets/js/collaborative-editor/stores/createAdaptorStore.ts"
  - "assets/js/collaborative-editor/types/adaptor.ts"
  - ".context/adaptors/**"
---

# Adaptors: which documents to trust

Most of `.context/adaptors/` is archaeology from designs that were abandoned before they
shipped. Grep will find it and it reads convincingly. Everything at the top level of that
folder is current, and there are six things:

- `README.md` — the entry point, and the shortest thing to read.
- `ATLAS.md` — the architecture in eight diagrams, stamped with the commit it describes.
  Start here to understand the shape of the subsystem.
- `REWRITE-2026-05.md` — the canonical spec. Per-callback contracts and the reasoning behind
  each decision. Grep it, don't read it end to end.
- `BEHAVIOURS.md` — the subsystem's promises, one section per behaviour, each stating what
  holds today and what observation would settle it. Read it before treating something as a
  gap nobody noticed.
- `07-channel-live-update-findings-2026-06-03.md` — two decisions still open, still blocking.
- `NOTES.md` — a running log of open questions and irregularities hit while working on the
  subsystem, newest entry on top. Dated entries, none of them acted on yet. Read it before
  concluding you have found a new bug.

Everything under `.context/adaptors/archive/` is superseded, and every file there carries an
ARCHIVED banner saying why. Do not cite it, follow it, or use it to answer a question about
how the subsystem works. Two traps worth naming: `archive/ARCHITECTURE.md` diagrams the
abandoned PR #4473 design (blob table plus Oban) in convincing detail and shares almost
nothing with what shipped, and `archive/NOTES.md` is a dead namesake of the live `NOTES.md`
above — check which one you opened.

Live status is the PR, not the folder: `gh pr view 4801 --json body -q .body`. Don't
reconstruct that checklist anywhere else, and don't infer completion state from the archived
phase-A/phase-B PRDs — both phases shipped, so those describe code that already exists.

If you change the subsystem's shape, update `ATLAS.md` and move its commit stamp. A stale
architecture diagram is worse than none, because it misleads with confidence.

Process and naming conventions for this subsystem are a separate rule:
`.claude/rules/adaptors-otp.md`.
