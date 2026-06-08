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

### One ownership seam, three payoffs

Name-isolation (§1), deterministic teardown (§3), and async-safety (§2) are not
three problems — they are three payoffs of **one** seam. The root control is an
**injectable owning identity**: the process / atom / pid / name that owns the
thing. Make that a parameter and all three follow:

- **Name-isolation** — an anonymous or per-test name means no
  `{:already_started, _}` clash, so the suite runs `async: true`.
- **Deterministic teardown** — bind the owner to the test (it holds the pid, or
  the process monitors a chosen owner) and the thing dies with its owner — no
  manual cleanup.
- **Async-safety** — that same injected owner is the pid you scope `Mox.allow`
  to (§2, Axis 2). Where the hop graph is deep you add the `Mox.allow`
  strategies, but the seam is the same one.

Lose the seam and you fight all three separately: a hardcoded name forces the
suite serial; a process with no symmetric `stop` and no owner to monitor leaks
past its test; a dependency fished from a global has no owner to lend a mock to.
The collaboration fix below (§3) is the cautionary example — it solved
*lifetime* in test support (an `on_exit` wrapper) instead of at the seam,
because the production API has no owner option yet. That works, but the seam
ended up in the test helper, not the API; the API-level owner option (§3,
option 1) is the fuller fix.

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

### Constructor sub-rule: `start_link`-style functions put the name in trailing opts

"Subject leads" governs functions that **address an already-running process**.
It does *not* govern **constructors** — `start_link` / `start_child` and
friends — and the constructor convention pulls the other way, just as
near-universally: the name goes in a **trailing `opts` keyword list**, never as
a leading positional.

```elixir
GenServer.start_link(module, init_arg, opts)    # name: in opts
Supervisor.start_link(children, opts)            # name: in opts
Agent.start_link(fun, opts)                      # name: in opts
Registry.start_link(opts)                        # name: in opts
Oban.start_link(opts) / Finch.start_link(opts)   # name: in opts
```

Every `start_link` in the standard library, and across Oban, Phoenix.PubSub and
Finch, puts `name:` in opts. So the two rules never actually collide — they
govern **mutually exclusive function shapes**:

- a function that **creates** a process → name in trailing `opts`
  (`def start_link(arg, opts \\ [])`);
- a function that **operates on** an existing one → instance leads positionally
  (`def fetch(server \\ __MODULE__, key)`).

You never call `start_link` on a running process, and you never need a
name-in-opts on `call` / `lookup`. The *identity-vs-configuration* question does
not change this: whether the name is **intrinsic identity** (the key a
`Registry` registers under) or an **instance selector** (which `Oban` to talk
to), the constructor still takes it in opts. What flips is only the call side —
`Oban` leads with the instance for `insert(name \\ Oban, changeset)`.

One nuance worth stating, because it is the thing that confuses people: the
**process-registration name** (the `:via` tuple, the registered atom, the
`name:` opt) is what goes in trailing opts. **Domain data that happens to
identify the thing** (a workflow id, a `document_name`) is just an `init_arg`
payload and stays positional. `Lightning.Collaborate.start_document/2` already
gets this right — `document_name` is a positional payload, while the registered
name lives in opts inside the child spec:

```elixir
def start_document(%Workflow{} = workflow, document_name) do
  SessionSupervisor.start_child(
    {DocumentSupervisor,
     workflow: workflow,
     document_name: document_name,
     name: Registry.via({:doc_supervisor, document_name})}  # name → opts
  )
end
```

So a new document entrypoint that also takes an **owner** (for owner-monitored
cleanup, §3) resolves cleanly: the owner is process configuration, so it joins
the registration name in opts — `start_document(workflow, document_name, opts \\ [])`
with `owner:` in `opts` — *not* threaded as a leading positional. Its
call/lookup partners (`stop_document/1`, `whereis/1`) keep the subject first,
per the main rule.

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

### Lifetime/ownership: how a dynamic process gets torn down in a test

§1's teardown story — `start_supervised!` hands the test the pid, ExUnit stops
it on exit — works *because that process is a fixed singleton owned by its
starter*. A §3 process is the opposite by design: started under a global
`DynamicSupervisor`, keyed by runtime data, **meant to outlive the caller** that
started it. ExUnit does not own it, so nothing tears it down when the test ends.
And if it touches a test-scoped resource — a DB write, say — it does so *after*
the test's Ecto-sandbox owner has exited, crashing with `owner ... exited` and
poisoning the next test. This is a real flake the Lightning collaboration suite
hit: a document started via `Collaborate.start/1` is owned by the global
`SessionSupervisor` DynamicSupervisor, outlived its test, and wrote to the DB
after teardown.

Two recipes, in order of preference.

**Option 1 (preferred) — owner-monitored self-cleanup on the production API.**
Generalise the `commanded/eventstore` owner-monitor pattern from "config row
self-deletes" to "process tree self-terminates": let the dynamic `start` take an
optional `owner` pid, `Process.monitor/1` it, and stop the process when that
owner goes `:DOWN`. Then *any* caller — a test, a LiveView, a short-lived
request — gets deterministic cleanup for free by passing `owner: self()`, and
tests need no special wrapper. This is the §0 seam landed in the API: one owner
parameter buys lifetime *and* (with a per-test name) async-isolation, the same
control plane.

**Option 2 (what the collaboration fix did) — public symmetric `stop` + a test
helper that binds it.** When the API has no owner option yet, add a
deterministic, idempotent public `stop` (the partner to the dynamic `start`),
then bind it to the test in test support with `on_exit`:

```elixir
# lib/lightning/collaboration.ex — the symmetric public stop, idempotent
@spec stop_document(document_name :: String.t()) :: :ok
def stop_document(document_name) do
  case Registry.whereis({:doc_supervisor, document_name}) do
    nil ->
      :ok

    pid ->
      try do
        DocumentSupervisor.stop(pid)
        :ok
      catch
        :exit, _ -> :ok
      end
  end
end
```

```elixir
# lib/lightning/collaboration/document_supervisor.ex — synchronous graceful stop.
# GenServer.stop(:normal) guarantees terminate/2 runs the flush, unlike the
# DynamicSupervisor's :shutdown; :transient restart means a :normal exit is not
# restarted.
def stop(pid, timeout \\ 5_000) when is_pid(pid) do
  GenServer.stop(pid, :normal, timeout)
end
```

```elixir
# test/support/collaboration_helpers.ex — reconstruct start_supervised's
# lifetime-binding at the test boundary
def start_collaboration_document(
      %Lightning.Workflows.Workflow{} = workflow,
      document_name
    )
    when is_binary(document_name) do
  on_exit(fn -> Lightning.Collaborate.stop_document(document_name) end)
  Lightning.Collaborate.start_document(workflow, document_name)
end
```

The helper *is* the §0 seam, but living in test support rather than the API. It
works, and the symmetric `stop` is worth having regardless — production needs
deterministic teardown too (`Collaborate.start/1` calls `stop_document/1` to
clean up a document it orphaned when a session fails to attach). But every new
call site must *remember* to use the helper; the owner-monitored option (1)
needs no wrapper and protects every caller, which is why it is the fuller fix.
Either way, keep a blanket `stop_all_collaboration_documents/0` `on_exit` net as
belt-and-braces for serial (`async: false`) suites — it catches a single
un-bound leak before it corrupts the next test.

---

## 4. Anti-patterns checklist (point the harness here)

- ❌ `name: __MODULE__` hardcoded *inside* `start_link` on a worker. → Make
  `:name` an option defaulting to `__MODULE__`.
- ❌ Public API calling `GenServer.call(__MODULE__, …)` with no server arg. →
  `def fn(server \\ __MODULE__, …)`, server first.
- ❌ Putting the registered name as a leading positional on a constructor
  "because the subject leads." → Constructors take `name:` (and `owner:`) in
  trailing opts; "subject leads" is the rule for `call` / `lookup` only. Domain
  data (a workflow id) can still be a positional payload.
- ❌ A dynamically-supervised process that must outlive its caller, with no
  deterministic teardown — it outlives the test and crashes on a post-teardown
  resource (e.g. a DB write after the Ecto-sandbox owner has exited). → Give it
  an owner-monitored self-cleanup option (preferred), or a public symmetric
  `stop` bound to the test via `on_exit`; keep a blanket sweep as
  belt-and-braces for serial suites.
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
  `lib/event_store/config/store.ex` (ETS-per-instance, owner-monitored). The
  owner-monitor idea generalises beyond a config row: monitor a chosen owner and
  have the whole *process tree* self-terminate on its `:DOWN` (§3, option 1).
- [`Registry`](https://hexdocs.pm/elixir/Registry.html) ·
  [Thoughtbot — dynamic process names](https://thoughtbot.com/blog/how-to-start-processes-with-dynamic-names-in-elixir)
- Constructor vs call/lookup argument order — `start_link` puts `name:` in
  trailing opts across the stdlib and ecosystem, while `call`/`lookup`/`insert`
  lead with the instance:
  [`GenServer`](https://hexdocs.pm/elixir/GenServer.html) ·
  [`Supervisor`](https://hexdocs.pm/elixir/Supervisor.html) ·
  [`Agent`](https://hexdocs.pm/elixir/Agent.html) ·
  [`Oban`](https://hexdocs.pm/oban/Oban.html) ·
  [`Phoenix.PubSub`](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html) ·
  [`Finch`](https://hexdocs.pm/finch/Finch.html).
- In-repo: `lib/lightning/adaptors/supervisor.ex`,
  `lib/lightning/collaboration.ex`,
  `lib/lightning/collaboration/registry.ex`,
  `lib/lightning/collaboration/document_supervisor.ex`,
  `test/support/collaboration_helpers.ex`.
