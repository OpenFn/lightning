defmodule Lightning.Adaptors.EndToEndBroadcastTest do
  @moduledoc """
  A `{:changed, name, source}` broadcast on the per-instance source topic
  (shared by `Scheduler` and `Invalidator` for cache coherence) must reach
  the per-instance client topic (which `WorkflowChannel` subscribers use
  for display freshness) as a single coalesced `adaptors_updated` envelope.

  This is the only test that exercises the full wiring across Invalidator,
  NodeMonitor, ChannelBroadcaster, and Scheduler.
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

    assert_receive %{
                     event: "adaptors_updated",
                     payload: %{names: ["@openfn/language-test"]}
                   },
                   ChannelBroadcaster.debounce_ms() + 200
  end
end
