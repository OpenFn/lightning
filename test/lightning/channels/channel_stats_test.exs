defmodule Lightning.Channels.ChannelStatsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Channels
  alias Lightning.Channels.SearchParams

  describe "get_channel_stats_for_project/1" do
    test "returns zeros for a project with no channels" do
      project = insert(:project)

      assert %{total_channels: 0, total_requests: 0} =
               Channels.get_channel_stats_for_project(project.id)
    end

    test "counts channels and sums requests across all channels" do
      project = insert(:project)
      channel1 = insert(:channel, project: project)
      channel2 = insert(:channel, project: project)
      {:ok, snapshot1} = Channels.get_or_create_current_snapshot(channel1)
      {:ok, snapshot2} = Channels.get_or_create_current_snapshot(channel2)

      insert(:channel_request,
        channel: channel1,
        channel_snapshot: snapshot1,
        state: :success
      )

      insert(:channel_request,
        channel: channel1,
        channel_snapshot: snapshot1,
        state: :success
      )

      insert(:channel_request,
        channel: channel2,
        channel_snapshot: snapshot2,
        state: :success
      )

      assert %{total_channels: 2, total_requests: 3} =
               Channels.get_channel_stats_for_project(project.id)
    end

    test "does not count requests from other projects" do
      project = insert(:project)
      other_channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(other_channel)

      insert(:channel_request,
        channel: other_channel,
        channel_snapshot: snapshot,
        state: :success
      )

      assert %{total_requests: 0} =
               Channels.get_channel_stats_for_project(project.id)
    end
  end

  describe "SearchParams.new/1" do
    test "parses valid UUID and ignores invalid or unknown keys" do
      uuid = Ecto.UUID.generate()

      # Empty map returns nil channel_id
      assert %SearchParams{channel_id: nil} = SearchParams.new(%{})

      # Valid UUID is accepted
      assert %SearchParams{channel_id: ^uuid} =
               SearchParams.new(%{"channel_id" => uuid})

      # Invalid UUID is silently dropped
      assert %SearchParams{channel_id: nil} =
               SearchParams.new(%{"channel_id" => "not-a-uuid"})

      # Unknown keys are silently dropped
      assert %SearchParams{channel_id: nil} =
               SearchParams.new(%{"unknown_key" => "value"})
    end
  end
end
