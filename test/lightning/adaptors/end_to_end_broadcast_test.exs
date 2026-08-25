defmodule Lightning.Adaptors.EndToEndBroadcastTest do
  @moduledoc """
  Phase A closeout — §6.5c integration smoke.

  A `{:changed, name, source}` broadcast on the per-instance source
  topic (the cache-coherence audience that the `Scheduler` and
  `Invalidator` share) must traverse the wired stack and arrive on
  the per-instance client topic (the display-freshness audience that
  `WorkflowChannel` subscribers listen to) as a single coalesced
  `adaptors_updated` envelope.

  This is the only assertion that breaks if any of the four newly-wired
  Supervisor children (Invalidator, NodeMonitor, ChannelBroadcaster,
  Scheduler) is misconfigured for the boot path.
  """

  use Lightning.DataCase, async: false

  alias Lightning.Adaptors.ChannelBroadcaster
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  test "PubSub source-topic broadcast reaches client topic as coalesced envelope" do
    sup = :"e2e_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.Local}
    )

    source_topic = AdaptorsSupervisor.source_topic(sup)
    client_topic = AdaptorsSupervisor.client_topic(sup)

    :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, client_topic)

    :ok =
      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        source_topic,
        {:changed, "@openfn/language-test", :local}
      )

    # The ChannelBroadcaster fans out a map envelope (see
    # `Lightning.Adaptors.ChannelBroadcaster.handle_info(:flush, _)`).
    # The DB is empty in this case → `Store.packages/1` returns
    # `{:ok, []}` → an empty-list envelope is broadcast.
    assert_receive %{event: "adaptors_updated", payload: %{adaptors: _}},
                   ChannelBroadcaster.debounce_ms() + 200
  end
end
