---
type: reference
status: active
date: 2026-05-19
related:
  - "[[elixir]]"
tags:
  - elixir
  - otp
  - testing
---

# Testable Supervision Trees & Named Processes

Guidance for building supervision trees, supervisors, GenServers and named
processes that are **uniquely addressable and isolated in tests** (so the suite
runs `async: true`) but **need no name in normal production use**.

This exists because AI harnesses (and people in a hurry) reliably reach for the
shortcut — `name: __MODULE__` baked into the process, dependencies fished out
of global state — which works in dev, looks idiomatic, and quietly forces the
whole test suite serial. Point Claude at this doc when generating or reviewing
OTP code.

---

## 0. The principle

**A process's name, and its dependencies, are *parameters* — not constants.**

Every failure mode here traces to one shortcut: hardcoding the name inside the
process, or resolving a collaborator from global state at call time, instead of
threading it through structure (supervision wiring, `start_link` opts, process
state, the caller signature).

Useful framing from Gray & Tate, *Designing Elixir Systems with OTP* ("Do Fun
Things with Big, Loud Worker-Bees"): push logic into a pure functional core
that needs no processes to test, so the GenServer is a thin shell. Everything
below is damage control for the thin shell that remains.

> **Scope guard.** Often the cleanest fix is that a thing never needed to be a
> process or a stored value at all. That's worth one sentence at the design
> review, then move on. The objective of this document is the **caller
> signature and how information reaches child processes** — not relitigating
> whether something should be a GenServer.

---

## 1. The 101 case: fixed children, no Registry

A `Registry` is a lookup table from a **domain key → pid**. You need one only
when *all three* hold:

1. an **arbitrary / open-ended** number of the process exists,
2. keyed by **runtime data** (a workflow id, a session id), and
3. the code that must talk to one **does not already hold its pid**.

A supervisor with a **fixed, known set of children** — one of each — fails all
three. It needs nothing. The realisation:

> For a constant set of children, **the registered module-atom name *is* your
> registry, and it's free.** A registered name already survives restarts — the
> supervisor brings the child back and it re-registers the same atom. That is
> the one feature people reach to `Registry` for.

The whole 101 pattern, no Registry, fully async-isolatable:

```elixir
defmodule MyApp.Cache do
  use GenServer

  # name is an OPTION, defaulted — never hardcoded inside the module
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # API takes the server ref FIRST, defaulted to the singleton
  def fetch(server \\ __MODULE__, key), do: GenServer.call(server, {:fetch, key})

  @impl true
  def init(opts) do
    # dependencies are injected, with prod defaults — never read from a global
    {:ok, %{store: %{}, http: Keyword.get(opts, :http, MyApp.HTTP)}}
  end
end
```

Production (in the app supervisor's fixed child list) gets the singleton for
free; callers write `MyApp.Cache.fetch(key)` and never name anything. The test
never *looks anything up* — it **holds the pid it just started**:

```elixir
test "expires entries" do
  pid = start_supervised!({MyApp.Cache, name: nil, http: HTTPMock})
  assert MyApp.Cache.fetch(pid, :missing) == nil
end
```

`name: nil` is the trick: it starts an anonymous, isolated instance even when
the app already booted a global `MyApp.Cache`, so there is no
`{:already_started, _}` clash, no need to gut `application.ex` in test config,
and the test stays `async: true`. (Only reach for config-driven "don't boot it
in `:test`" when something you *cannot* hand a pid — a Plug, a distant caller —
calls the API with the default name. That is the exception, not the default.)

### Argument order convention: server ref first, with a default

This is the OTP-wide convention and it is near-universal:
`GenServer.call(server, …)`, `Agent.get(agent, …)`,
`Registry.lookup(registry, …)`, `Phoenix.PubSub.broadcast(pubsub, …)`,
`Oban.insert(name \\ Oban, changeset)`, `Mox.allow(mock, …)`,
`Ecto.Adapters.SQL.Sandbox.allow(repo, …)` — the addressed thing is the
**subject**, so it leads.

Critically, **first-with-default is the idiom that produces the `/1` + `/2`
pair cleanly**:

```elixir
def fetch(server \\ __MODULE__, key)
# fetch(key)      -> arity 1, server defaults to __MODULE__   (production)
# fetch(pid, key) -> arity 2, explicit instance               (test)
```

Production never names anything; the test injects a pid through the *same*
function. **The signature is the injection seam.** That is why this convention
is load-bearing, not stylistic.

The one principled exception: **pipeline-first APIs put the instance last** —
`Finch.build(:get, url) |> Finch.request(MyFinch)` — because the data being
transformed is the subject and the instance is configuration, so it reads in a
pipe. Rule of thumb: *callers piping data through it → instance last; callers
addressing a process → instance first (the common case).*

---

## 2. The two axes (the centrepiece)

People — and AI harnesses — reliably weld together two **independent** problems.
Welding them is what makes refactors thrash. Keep them apart:

1. **Axis 1 — where does per-instance config / identity live?**
2. **Axis 2 — which process actually invokes the injected dependency?**

`:persistent_term` (and runtime `Application.put_env`, and naked global ETS) is
the wrong answer to **Axis 1**. The `set_mox_global` / `async: false` /
`Sandbox.allow` pain is entirely **Axis 2**. Fixing Axis 1 does not fix Axis 2
— but it makes Axis 2 *legible*, which is the precondition for fixing it.

### `:persistent_term` is a smell

Treat `:persistent_term`, runtime `Application.put_env`, and naked global ETS
for per-instance config as a **smell requiring explicit justification**. Its
presence means someone reached for *stored state* when *structure* is the
functional answer. The legitimacy litmus:

> **Does this value ever need to differ between two tests running at the same
> time?** If yes, it cannot live in any global store — inject it. If no, and
> it is genuinely hot-read and fixed at boot, `:persistent_term` is fine
> (Phoenix/Ecto use it internally for exactly that).

### Worked example: `Lightning.Adaptors.Supervisor`

The adaptors supervisor is otherwise *exemplary* — its moduledoc states the
principle verbatim, it derives every child name via `Module.concat(name, …)`
(a fixed child set with full multi-instance async isolation and **zero
Registry**), and it injects the `:strategy` as an explicit opt with a
production default. One wart:

```elixir
# supervisor.ex init/1 — strategy & source are LOCALS here…
strategy = Keyword.get(opts, :strategy, Config.strategy())
:persistent_term.put(meta_key(name), %{strategy: strategy, source: source_for(strategy)})
# …then the same init/1 injects cache/tasks/source_topic into child specs
# explicitly, two lines down — but routes strategy/source through a global.
```

`Scheduler` then re-fetches it from that global *at call time*:

```elixir
# scheduler.ex — strategy materialises from nowhere, with no traceable owner
strategy = AdaptorsSupervisor.strategy(state.sup)   # :persistent_term.get/1
strategy.fetch_adaptor(name)
```

An investigation of every call site classified this **case (b): avoidable**.
Nothing reaching `Store` lacks the strategy/source at a point where it is
knowable; there is exactly one hardcoded production instance, so even the
stateless facade-from-web path collapses to "boot config for the one instance,"
not a dynamic lookup. The generalisable tell:

> **Global storage smuggling a value past a structural boundary that was
> already open two lines away and already carrying its siblings across.**

The fix is Axis 1: inject `strategy`/`source` into the child specs the
supervisor is *already building* (it has them in scope), and let `Scheduler`
hold them in its state — exactly as it already does for `source` at `init/1`.

### Why that makes Axis 2 legible

Before: you cannot tell *which process* will call `StrategyMock`, because the
value appears from a global with no owner — so you reach for `set_mox_global`
and the suite goes serial.

After injection: `Scheduler` visibly owns the strategy in its state, so the
mock's caller is obvious and you can scope the allowance:

```elixir
# Axis 2 recipe — explicit allowance, async-safe
pid = start_supervised!({Lightning.Adaptors.Supervisor,
                          name: name, strategy: StrategyMock})
Mox.allow(StrategyMock, self(), Process.whereis(scheduler_name(name)))
```

When the pid does not exist yet at setup time (leader election, lazy start),
use the **deferred-resolver form** of `Mox.allow/3` — the trick people forget:

```elixir
Mox.allow(StrategyMock, self(), fn ->
  :global.whereis_name(scheduler_name(name))
end)
```

Mox resolves the pid lazily on first mock invocation, sidestepping the race.
Tasks started via `Task.Supervisor.async/async_nolink` carry `$callers`, so
Mox walks back to the allowed parent automatically; `start_child`
(fire-and-forget) does not propagate and needs its own allowance.

`Mox.allow/3` and `Ecto.Adapters.SQL.Sandbox.allow/3` are **one concept** —
same signature, same ownership model (a test owns a resource and explicitly
lends it to processes it spawns). Mox's was modelled on Ecto's.

> **When `set_mox_global` is legitimate, not a cop-out:** explicit allow is the
> default; its cost scales with how many *process hops* the mocked call
> traverses and how *dynamic* those pids are. `set_mox_global` (forcing
> `async: false` for that case) is the correct escape hatch when the hop graph
> is dynamic and deep — `HighlanderPG`-wrapped leader election is the textbook
> case. Try the deferred-resolver form *first*; most cases are not Highlander.

---

## 3. Dynamic populations: when a Registry *is* earned

When the population is genuinely open-ended and keyed by runtime data, and the
caller does not hold the pid — `DynamicSupervisor` + `Registry` + `:via`.
`Lightning.Collaborate` is the worked example: N sessions/documents keyed by
`document_name`, looked up by a LiveView that did not start them.

```elixir
SessionSupervisor.start_child(
  {Session, workflow: workflow, user: user,
   name: Registry.via({:session, "#{document_name}:#{session_id}", user.id})}
)
```

Two valid shapes, document the trade-off:

- **One Registry per top-level instance** (Oban): perfect isolation, but the
  instance name threads through every public function
  (`Oban.insert(MyApp.Oban, …)`).
- **One global Registry, key-namespaced** (Lightning collaboration): the public
  API stays clean (`Collaborate.start/1` takes no name); isolation depends on
  keys being genuinely unique. Correct when identity is naturally unique
  (workflow + session); risky if a test can reuse a key.

### The "earned name → config lookup" reference

If a **stateless synchronous** caller genuinely holds only a name *and* the
population is dynamic, a name → config lookup is justified — and even then it
is **ETS-per-instance, never `:persistent_term`**. `commanded/eventstore` hit
this exact requirement and chose: one named ETS table (`read_concurrency:
true`) owned by a GenServer, holding `{name, pid, ref, store, config}`, the
owner pid monitored so the row **self-deletes on shutdown**. It explicitly
rejected `:persistent_term` because instances churn under async tests and
`:persistent_term` writes/erases trigger a global GC scan. The bonus: an
owner-monitored ETS table needs no manual cleanup function (cf. the adaptors
`forget/1` wart and its "we don't call this automatically because GC is
expensive" comment).

---

## 4. Anti-patterns checklist (point the harness here)

- ❌ `name: __MODULE__` hardcoded *inside* `start_link` on a worker. → Make
  `:name` an option defaulting to `__MODULE__`.
- ❌ Public API calling `GenServer.call(__MODULE__, …)` with no server arg. →
  `def fn(server \\ __MODULE__, …)`, server first.
- ❌ Dependencies / per-instance config read from `:persistent_term` /
  runtime `Application.put_env` / global ETS at call time. → Inject via
  `start_link` opts → `init/1` → process state, or thread through the child
  spec. Litmus: *does it vary per concurrent test?*
- ❌ Global storage used to pass a value the supervisor already had in scope
  one child-spec away. → Inject it into the child spec.
- ❌ `set_mox_global` reached for reflexively to "fix" a boundary. → Try
  `Mox.allow(mock, self(), pid)`, then the deferred-resolver form; reserve
  global for genuinely dynamic/deep hop graphs.
- ❌ A `Registry` added to a *fixed* child set "to name things." → The
  registered atom name already does this, free.
- ❌ Testing GenServer internals via raw `:"$gen_call"` / poking state. →
  Test through the public API; test logic in a pure core module.
- ❌ App supervisor that cannot be started piecemeal in tests. → Children
  startable independently via `start_supervised!`.

---

## References

- Gray & Tate, *Designing Elixir Systems with OTP* (Pragmatic Bookshelf) —
  functional core / boundary layering.
- Saša Jurić, *Elixir in Action* — process registration as a parameter; `:via`.
- [Oban — instance & DB isolation](https://hexdocs.pm/oban/isolation.html) ·
  [`Oban.Registry`](https://hexdocs.pm/oban/Oban.Registry.html)
- [`Ecto.Adapters.SQL.Sandbox`](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html)
  — ownership / `allow/3`.
- [Mox docs](https://hexdocs.pm/mox/Mox.html) — `allow/3`, deferred resolver,
  `set_mox_from_context`.
- [`commanded/eventstore`](https://github.com/commanded/eventstore) —
  `lib/event_store/config/store.ex` (ETS-per-instance, owner-monitored).
- [`Registry`](https://hexdocs.pm/elixir/Registry.html) ·
  [Thoughtbot — dynamic process names](https://thoughtbot.com/blog/how-to-start-processes-with-dynamic-names-in-elixir)
- In-repo: `lib/lightning/adaptors/supervisor.ex`,
  `lib/lightning/collaboration.ex`,
  `lib/lightning/collaboration/registry.ex`.
