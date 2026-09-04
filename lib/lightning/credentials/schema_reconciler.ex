defmodule Lightning.Credentials.SchemaReconciler do
  @moduledoc """
  Sweeps legacy short-form credential `schema` names to their full npm
  package names whenever the adaptor catalogue might have grown enough to
  resolve one, via `Lightning.Credentials.reconcile_legacy_schema_names/1`.

  Runs once on start **and** on every `adaptors_updated` broadcast. The
  broadcast (`Lightning.Adaptors.ChannelBroadcaster`) only fires when an
  adaptor row actually changes, so a catalogue that is already warm (e.g.
  after a restart, backed by a persistent store) may complete its first
  refresh without changing a single row and would never emit anything — a
  subscriber that waited only for the broadcast would then never sweep. The
  on-start run covers that case.

  The sweep is idempotent (each pass only touches rows still on a short
  name), so running it twice, from two triggers, or on every node in a
  cluster (the PubSub topic is cluster-wide) is safe. There is deliberately
  no "done" flag gating it — that flag was the bug this module replaces: it
  could get set after a failed run and then never retry.

  Each sweep issues a `SELECT DISTINCT schema` over `credentials` (no index
  on that column) plus one catalogue lookup per distinct legacy name, and
  every node runs it on every broadcast. Cheap at current table sizes;
  revisit if `credentials` or broadcast frequency grow enough to matter.
  """

  use GenServer

  alias Lightning.Credentials

  require Logger

  @default_retry_ms :timer.minutes(5)

  @doc """
  Starts the reconciler. Required opts: `:name`, `:sup`. Optional:
  `:reconcile` (1-arity fn, default
  `&Lightning.Credentials.reconcile_legacy_schema_names/1`) and `:retry_ms`
  (default 5 minutes) controlling the retry delay after a failed sweep.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    sup = Keyword.fetch!(opts, :sup)

    reconcile =
      Keyword.get(opts, :reconcile, &Credentials.reconcile_legacy_schema_names/1)

    retry_ms = Keyword.get(opts, :retry_ms, @default_retry_ms)

    :ok = Lightning.Adaptors.subscribe_to_updates(sup)
    send(self(), :reconcile)

    {:ok, %{sup: sup, reconcile: reconcile, retry_ms: retry_ms, retry_ref: nil}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    {:noreply, run(state)}
  end

  def handle_info(%{event: "adaptors_updated"}, state) do
    {:noreply, run(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Cancels any pending retry so a run triggered by a broadcast (or a
  # concurrent :reconcile) never leaves two retry chains ticking.
  defp run(state) do
    if state.retry_ref, do: Process.cancel_timer(state.retry_ref)
    state.reconcile.(state.sup)
    %{state | retry_ref: nil}
  rescue
    error ->
      Logger.warning(
        "SchemaReconciler: sweep failed, retrying in #{state.retry_ms}ms: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      %{
        state
        | retry_ref: Process.send_after(self(), :reconcile, state.retry_ms)
      }
  end
end
