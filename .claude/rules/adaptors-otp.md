---
paths:
  - "lib/lightning/adaptors.ex"
  - "lib/lightning/adaptors/**/*.ex"
  - "test/lightning/adaptors_test.exs"
  - "test/lightning/adaptors/**/*.exs"
---

# Adaptors: naming and dependency injection

Every process in this subsystem derives its name from the single `:name` opt passed
to `Lightning.Adaptors.Supervisor`. Nothing is hardcoded, which is what lets the
integration suite run isolated instances in one BEAM under `async: true`. Adding a
process that breaks this forces the whole suite serial.

When adding or changing a process here:

- Take `:name` from opts (`Keyword.fetch!(opts, :name)`) and derive any child,
  cache, topic or lock name from it. Follow the helpers at
  `lib/lightning/adaptors/supervisor.ex:116-173`.
- Add it to the fixed child list in `init/1` (`supervisor.ex:67-85`) with its
  collaborators passed in the child spec. Do not add a `Registry`: the child set is
  fixed and the registered atom already addresses it.
- Public functions that talk to a running process lead with the server ref,
  defaulted: `def refresh(sup \\ Config.default_instance(), name)`. `start_link`
  takes `name:` in trailing opts.
- `Lightning.Adaptors.Config.default_instance/0` is what production code and
  every public `Lightning.Adaptors` function default their `sup` argument
  through, not a hardcoded module attribute. Tests get a private instance with
  `setup :isolated_adaptors` (from `Lightning.AdaptorTestHelpers`), which
  starts a fresh supervisor and stubs `default_instance/0` to it, instead of
  touching the global instance. For an `async: true` module, that stub only
  reaches processes reachable via `$callers` (`Task`, `start_supervised!`,
  ...); a process spawned outside that chain, or already running, still
  sees the real global instance. An `async: false` module gets Mimic's
  global mode instead, which reaches every process in the VM.
- The `Scheduler` is a cluster singleton behind `HighlanderPG` and registers under
  `global_scheduler_name/1` (`supervisor.ex:149`). `Process.whereis` will not find
  it.

Known wart, do not copy it: `strategy` and `source` are published to
`:persistent_term` in `init/1` (`supervisor.ex:40-43`) and re-read at call time by
`Scheduler` (`scheduler.ex:259`, `:271`, `:313`) and `Store`. New code should
take them from process state or the child spec instead. `Scheduler` already does
this correctly for `source` (`scheduler.ex:113`, `:132`).

In tests, prefer `Mox.allow(StrategyMock, self(), pid)` and keep `async: true`, as
`test/lightning/adaptors/store_test.exs:135` does. `set_mox_global` costs the file
its async, and is only justified where the hop graph is genuinely dynamic, as in
`highlander_integration_test.exs:27`.

Full reasoning: `.claude/guidelines/testable-supervision-trees.md`.
