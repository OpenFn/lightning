defmodule Lightning.ChannelsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Channels
  alias Lightning.Channels.Channel

  describe "list_channels_for_project/1" do
    test "returns channels for a project ordered by name" do
      project = insert(:project)
      insert(:channel, project: project, name: "bravo")
      insert(:channel, project: project, name: "alpha")
      insert(:channel, project: build(:project), name: "other")

      channels = Channels.list_channels_for_project(project.id)

      assert length(channels) == 2
      assert [%Channel{name: "alpha"}, %Channel{name: "bravo"}] = channels
    end

    test "returns empty list when project has no channels" do
      project = insert(:project)
      assert Channels.list_channels_for_project(project.id) == []
    end
  end

  describe "get_channel!/1" do
    test "returns the channel" do
      channel = insert(:channel)
      assert Channels.get_channel!(channel.id).id == channel.id
    end

    test "raises on not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_channel/1" do
    test "creates a channel with valid attrs" do
      project = insert(:project)

      assert {:ok, %Channel{} = channel} =
               Channels.create_channel(%{
                 name: "my-channel",
                 sink_url: "https://example.com/sink",
                 project_id: project.id
               })

      assert channel.name == "my-channel"
      assert channel.enabled == true
      assert channel.lock_version == 1
    end

    test "returns error on missing required fields" do
      assert {:error, changeset} = Channels.create_channel(%{})
      assert %{name: _, sink_url: _, project_id: _} = errors_on(changeset)
    end

    test "returns error for non-URL sink_url" do
      project = insert(:project)

      assert {:error, changeset} =
               Channels.create_channel(%{
                 name: "bad-sink",
                 sink_url: "not a url",
                 project_id: project.id
               })

      assert %{sink_url: ["must be a valid URL"]} = errors_on(changeset)
    end

    test "returns error for non-http scheme sink_url" do
      project = insert(:project)

      assert {:error, changeset} =
               Channels.create_channel(%{
                 name: "ftp-sink",
                 sink_url: "ftp://example.com",
                 project_id: project.id
               })

      assert %{sink_url: ["must be either a http or https URL"]} =
               errors_on(changeset)
    end

    test "accepts valid http and https sink_urls" do
      project = insert(:project)

      assert {:ok, _} =
               Channels.create_channel(%{
                 name: "http-sink",
                 sink_url: "http://example.com/path",
                 project_id: project.id
               })

      assert {:ok, _} =
               Channels.create_channel(%{
                 name: "https-sink",
                 sink_url: "https://example.com/path",
                 project_id: project.id
               })
    end

    test "returns error on duplicate name within project" do
      channel = insert(:channel)

      assert {:error, changeset} =
               Channels.create_channel(%{
                 name: channel.name,
                 sink_url: "https://example.com/other",
                 project_id: channel.project_id
               })

      assert %{project_id: _} = errors_on(changeset)
    end
  end

  describe "update_channel/2" do
    test "updates config fields and bumps lock_version" do
      channel = insert(:channel)

      assert {:ok, updated} =
               Channels.update_channel(channel, %{name: "new-name"})

      assert updated.name == "new-name"
      assert updated.lock_version == channel.lock_version + 1
    end

    test "returns stale error on lock_version conflict" do
      channel = insert(:channel)

      # Simulate concurrent update by updating lock_version in DB
      {1, _} =
        Lightning.Repo.update_all(
          from(c in Channel, where: c.id == ^channel.id),
          set: [lock_version: channel.lock_version + 1]
        )

      assert {:error, changeset} =
               Channels.update_channel(channel, %{name: "stale-update"})

      assert changeset.errors[:lock_version]
    end
  end

  describe "delete_channel/1" do
    test "deletes a channel with no snapshots" do
      channel = insert(:channel)
      assert {:ok, %Channel{}} = Channels.delete_channel(channel)

      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(channel.id)
      end
    end

    test "returns error when channel has snapshots referenced by requests" do
      channel = insert(:channel)
      snapshot = insert(:channel_snapshot, channel: channel)
      insert(:channel_request, channel: channel, channel_snapshot: snapshot)

      assert {:error, changeset} = Channels.delete_channel(channel)
      assert %{channel_snapshots: _} = errors_on(changeset)
    end
  end
end
