# Testable Supervision Trees & Named Processes

How to build supervisors, GenServers and named processes in Lightning so tests can
address them individually and the suite still runs `async: true`, while production
needs no name at all.

Targets **Elixir 1.18** (`mix.exs:8`) and **Mox 1.2** (`mix.exs:138`, test only).
Code is cited as `file:line` rather than transcribed, so read the source at the
citation instead of trusting a copy here.

## The anti-patterns

- **`name: __MODULE__` hardcoded inside `start_link`.** Make `:name` an option
  defaulting to `__MODULE__`, so a test can pass `name: nil` for an anonymous
  instance.
- **A public API calling `GenServer.call(__MODULE__, …)` with no server argument.**
  Write `def fetch(server \\ __MODULE__, key)`: server first, defaulted.
- **The registered name as a leading positional on a constructor.** Constructors
  take `name:` and `owner:` in trailing opts. "Subject leads" governs `call` and
  `lookup`, not `start_link`. Domain data (a workflow id, a document name) stays a
  positional payload.
- **A dynamically-supervised process with no deterministic teardown.** It outlives
  its test and crashes on a post-teardown resource, typically a DB write after the
  Ecto sandbox owner has exited. Give it an `owner:` option it monitors.
- **Per-instance config read from `:persistent_term`, runtime
  `Application.put_env`, or global ETS at call time.** Inject through `start_link`
  opts into `init/1` into process state. Litmus: does this value ever need to
  differ between two tests running at the same time?
- **Global storage passing a value the supervisor already had in scope one child
  spec away.** Put it in the child spec.
- **`set_mox_global` reached for reflexively.** Try `Mox.allow(mock, self(), pid)`
  first, then the deferred-resolver form.
- **A `Registry` added to a fixed child set to name things.** The registered atom
  already does that, free.
- **Testing GenServer internals by poking state or sending `:"$gen_call"`.** Test
  through the public API; test logic in a pure module that needs no process.

## The principle

A process's name, and its dependencies, are parameters rather than constants.
Every failure mode above comes from hardcoding the name inside the process, or
resolving a collaborator from global state at call time, instead of threading it
through structure: supervision wiring, `start_link` opts, process state, the caller
signature.

Per Gray & Tate's *Designing Elixir Systems with OTP*, push logic into a pure
functional core that needs no processes to test, so the GenServer stays a thin
shell. What follows is about that thin shell.

Often the cleanest fix is that a thing never needed to be a process at all. That is
worth one sentence at design review, then move on. The subject here is the caller
signature and how information reaches child processes, not whether something should
be a GenServer.

## 1. Fixed children: no Registry needed

A `Registry` maps a domain key to a pid. You need one only when all three hold:

1. an open-ended number of the process exists,
2. keyed by runtime data (a workflow id, a session id), and
3. the code that must talk to one does not already hold its pid.

A supervisor with a fixed, known set of children fails all three. For a constant
set of children the registered module-atom name *is* the registry, and it is free:
a registered name already survives restarts, since the supervisor brings the child
back and it re-registers the same atom.

The whole pattern, fully isolatable:

```elixir
defmodule MyApp.Cache do
  use GenServer

  # name is an option, defaulted, never hardcoded inside the module
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # server ref first, defaulted to the singleton
  def fetch(server \\ __MODULE__, key), do: GenServer.call(server, {:fetch, key})

  @impl true
  def init(opts) do
    # dependencies injected with production defaults, never read from a global
    {:ok, %{store: %{}, http: Keyword.get(opts, :http, MyApp.HTTP)}}
  end
end
```

Production puts it in the app supervisor's fixed child list and gets the singleton;
callers write `MyApp.Cache.fetch(key)` and name nothing. The test never looks
anything up, it holds the pid it just started:

```elixir
test "expires entries" do
  pid = start_supervised!({MyApp.Cache, name: nil, http: HTTPMock})
  assert MyApp.Cache.fetch(pid, :missing) == nil
end
```

`name: nil` is the part worth remembering. It starts an anonymous instance even
though the application already booted a global `MyApp.Cache`, so there is no
`{:already_started, _}` clash, no need to gut `application.ex` in test config, and
the test stays async. Only reach for "don't boot it in `:test`" config when
something you cannot hand a pid, such as a Plug or a distant caller, hits the API
with the default name.

### Argument order

Two rules that govern mutually exclusive function shapes, so they never collide:

- A function that **operates on** a running process leads with the instance,
  defaulted: `def fetch(server \\ __MODULE__, key)`. This matches
  `GenServer.call/2`, `Registry.lookup/2`, `Oban.insert/2` and
  `Ecto.Adapters.SQL.Sandbox.allow/3`.
- A function that **creates** a process takes the registration name in trailing
  opts: `GenServer.start_link(module, init_arg, opts)`, `Supervisor.start_link/2`,
  `Registry.start_link/1`.

First-with-default is what produces the `/1` + `/2` pair cleanly: production calls
arity 1 and names nothing, a test calls arity 2 with an explicit pid, through the
same function. That signature is the injection point, which is why the convention
is doing work rather than being cosmetic.

The one exception: pipeline-first APIs put the instance last, as in
`Finch.build(:get, url) |> Finch.request(MyFinch)`, because the data being
transformed is the subject.

Note the distinction between a **registration name** (a `:via` tuple, a registered
atom, the `name:` opt), which belongs in trailing opts, and **domain data that
identifies the thing** (a workflow id, a `document_name`), which is an `init_arg`
payload and stays positional. `Lightning.Collaborate.start_document/2..4`
(`lib/lightning/collaboration.ex:147-211`) is the worked example: `document_name`
is positional, while `owner:` and the registered name are opts, and its `@doc`
spells out why.

## 2. Injection versus global state

Two independent problems that get welded together, which is what makes refactors
thrash:

1. **Where does per-instance config live?**
2. **Which process actually invokes the injected dependency?**

`:persistent_term`, runtime `Application.put_env` and naked global ETS are wrong
answers to the first. The `set_mox_global` / `async: false` pain is entirely the
second. Fixing the first does not fix the second, but it makes the second legible,
which is the precondition for fixing it: once a process visibly holds its
dependency in state, you know which pid to lend the mock to.

Treat `:persistent_term` for per-instance config as needing explicit justification.
If the value ever needs to differ between two concurrent tests it cannot live in
any global store. If it does not, and it is genuinely hot-read and fixed at boot,
`:persistent_term` is fine; Phoenix and Ecto use it internally for exactly that.
The tell to watch for is global storage smuggling a value past a structural
boundary that was already open two lines away and already carrying its siblings
across.

`Lightning.Adaptors.Supervisor` shows both sides. `strategy` and `source` go
into `:persistent_term` keyed per instance (`lib/lightning/adaptors/supervisor.ex:40-43`),
which is the acceptable shape for the stateless `Store` functions: a caller
holding only the instance name has nowhere else to read boot-fixed config from.
It is the tell for `Scheduler`, whose child spec already carries `cache`,
`tasks` and `source_topic` (`supervisor.ex:57-62`) but not `strategy`, so the
process re-reads it from the global store on every refresh (`scheduler.ex:259`,
`:271`, `:313`). New children take config from the child spec, as `lock_key` does.

### Scoping mocks without going global

`Mox.allow/3` and `Ecto.Adapters.SQL.Sandbox.allow/3` are one concept with one
signature: a test owns a resource and explicitly lends it to processes it spawned.
Mox's was modelled on Ecto's.

Lightning's collaboration suite is the in-repo example, at
`test/support/collaboration_helpers.ex:93-125`. It grants the sandbox connection
and each per-test mock to a directly-started collaboration process, guarding every
`Mox.allow` so a test that never stubbed a given mock is unaffected. Its comment
records the migration: `set_mox_global` previously made every mock visible
cross-process, and under private Mox they are allowed explicitly. Private Mox via `set_mox_from_context` is the house default;
`grep -rn set_mox_global test/` lists the exceptions.

When the pid does not exist yet at setup time, because of leader election or a lazy
start, `Mox.allow/3` accepts a `(-> pid())` resolved lazily at first dispatch
(`deps/mox/lib/mox.ex:749-754`). It also accepts a registered name or `:via`
reference directly, so `Process.whereis` at setup time is usually unnecessary.

```elixir
Mox.allow(MyMock, self(), fn -> GenServer.whereis(Deferred) end)
```

Anything started through `Task` or `Task.Supervisor` carries `$callers`, including
`Task.Supervisor.start_child/3` and `/5`
(`task/supervisor.ex:527`, `:545` in Elixir 1.18), so Mox walks back to the allowed
parent without an explicit allowance. Processes started by other means do not.

`set_mox_global`, and the `async: false` that comes with it, is the correct escape
hatch when the hop graph is genuinely dynamic and deep. Try the deferred resolver
first.

## 3. Dynamic populations: when a Registry is earned

When the population is open-ended, keyed by runtime data, and the caller does not
hold the pid, use `DynamicSupervisor` + `Registry` + `:via`. Lightning's
collaboration tree is the worked example: N documents and sessions keyed by
`document_name`, looked up by a LiveView that did not start them.

The trade-off used to be between one Registry per top-level instance (Oban's
approach: perfect isolation, but the instance name threads through every public
function) and one global key-namespaced Registry (a clean public API, but isolation
rests on keys being unique). Lightning now does both, and the mechanism is worth
copying.

`Lightning.Collaboration.Instance` (`lib/lightning/collaboration/instance.ex`) is a
plain struct, no process, naming the three pieces one supervisor owns: its
Registry, its DynamicSupervisor, and its `:pg` scope. `default/0` pins them to the
application-wide singletons started in `application.ex:151`; `derive/1` builds an
isolated set from any other base name. The supervisor derives its instance from its
own name and threads it into every child spec
(`lib/lightning/collaboration/supervisor.ex:29-40`).

Public functions then take the instance as an **optional leading positional**, so
production calls stay clean and tests can address an isolated tree through the same
function: `stop_document(instance \\ Instance.default(), document_name)` at
`lib/lightning/collaboration.ex:132`. `Registry.via/2` and `Registry.whereis/2`
follow the same shape (`lib/lightning/collaboration/registry.ex:82`, `:122`).

Tests get an isolated tree from `start_collaboration_instance/0`
(`test/support/collaboration_helpers.ex:30-38`), which builds a unique base via
`System.unique_integer/1` and binds the tree's lifetime with `start_supervised!`.

### Lifetime: owner-monitored teardown

`start_supervised!` gives a test deterministic teardown because the process is a
fixed singleton owned by its starter. A dynamically-supervised process is the
opposite by design: it lives under a global `DynamicSupervisor` and is meant to
outlive the caller that started it. ExUnit does not own it, so nothing tears it
down at test end, and if it touches a test-scoped resource afterwards it crashes
with `owner ... exited` and poisons the next test. Lightning hit exactly this: a
document outlived its test and wrote to the DB after teardown.

The fix is an `owner:` option on the production API. `DocumentSupervisor` monitors
the pid if one is given, and stops `:normal` when it goes `:DOWN`, so `terminate/2`
runs the flush and `:transient` means no restart
(`lib/lightning/collaboration/document_supervisor.ex:67-71`, `:186-197`). It
defaults to `nil`, so production documents still outlive the LiveView that started
them.

Any caller now gets deterministic cleanup by passing `owner: self()`, with no
wrapper and nothing to remember in `on_exit`. That is what
`start_collaboration_document/2..3` does
(`test/support/collaboration_helpers.ex:59-76`).

Keep the symmetric public `stop` regardless: production needs deterministic
teardown too. `Collaborate.stop_document/1..2` is synchronous, idempotent, and
returns `:ok` whether or not a document is running
(`lib/lightning/collaboration.ex:123-145`), and `Collaborate.start/2` uses it to
tear down a document *that call created* when a session fails to attach, leaving
alone one it merely found (`lib/lightning/collaboration.ex:65-69`).

Get the timeout right on a synchronous stop. `DocumentSupervisor.stop/2` defaults
to 15s because `terminate/2` bounds each of its two children at 5s
(`lib/lightning/collaboration/document_supervisor.ex:43-51`). On timeout
`proc_lib:stop/3` exits the caller and leaves the target running, and
`stop_document` catches that exit and returns `:ok`, so too short a timeout reports
success while the flush is still in flight.

## References

- Gray & Tate, *Designing Elixir Systems with OTP* — functional core and boundary
  layering.
- Saša Jurić, *Elixir in Action* — process registration as a parameter, `:via`.
- [Oban isolation](https://hexdocs.pm/oban/isolation.html) ·
  [`Ecto.Adapters.SQL.Sandbox`](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html) ·
  [Mox](https://hexdocs.pm/mox/Mox.html) ·
  [`Registry`](https://hexdocs.pm/elixir/Registry.html)
- [`commanded/eventstore`](https://github.com/commanded/eventstore),
  `lib/event_store/config/store.ex` — owner-monitored ETS per instance, the idea
  the `owner:` option generalises. It rejected `:persistent_term` because instances
  churn under async tests and its writes trigger a global GC scan.
- In-repo: `lib/lightning/collaboration.ex`,
  `lib/lightning/collaboration/instance.ex`,
  `lib/lightning/collaboration/supervisor.ex`,
  `lib/lightning/collaboration/document_supervisor.ex`,
  `lib/lightning/collaboration/registry.ex`,
  `test/support/collaboration_helpers.ex`.
