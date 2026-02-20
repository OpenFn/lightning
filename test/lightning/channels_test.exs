defmodule Lightning.ChannelsTest do
  use Lightning.DataCase, async: true

  import Ecto.Query

  alias Lightning.Auditing.Audit
  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelAuthMethod
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Channels.ChannelSnapshot

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

  describe "list_channels_for_project_with_stats/1" do
    test "returns empty list for project with no channels" do
      project = insert(:project)

      assert Channels.list_channels_for_project_with_stats(project.id) == []
    end

    test "returns correct request_count and last_activity for a channel with requests" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      t1 = ~U[2025-01-01 10:00:00.000000Z]
      t2 = ~U[2025-01-02 12:00:00.000000Z]

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-stats-1",
        state: :success,
        started_at: t1
      })

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-stats-2",
        state: :success,
        started_at: t2
      })

      results = Channels.list_channels_for_project_with_stats(project.id)

      assert [
               %{
                 channel: %Channel{id: channel_id},
                 request_count: 2,
                 last_activity: ^t2
               }
             ] = results

      assert channel_id == channel.id
    end

    test "last_activity is nil when no requests exist" do
      project = insert(:project)
      insert(:channel, project: project)

      [result] = Channels.list_channels_for_project_with_stats(project.id)

      assert %{request_count: 0, last_activity: nil} = result
    end

    test "returns multiple channels ordered by name with independent stats" do
      project = insert(:project)
      channel_b = insert(:channel, project: project, name: "bravo")
      channel_a = insert(:channel, project: project, name: "alpha")

      {:ok, snapshot_b} = Channels.get_or_create_current_snapshot(channel_b)

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel_b.id,
        channel_snapshot_id: snapshot_b.id,
        request_id: "req-stats-3",
        state: :success,
        started_at: ~U[2025-06-01 00:00:00.000000Z]
      })

      results = Channels.list_channels_for_project_with_stats(project.id)

      assert [
               %{channel: %Channel{name: "alpha"}, request_count: 0},
               %{channel: %Channel{name: "bravo"}, request_count: 1}
             ] = results

      assert Enum.find(results, &(&1.channel.id == channel_a.id)).last_activity ==
               nil
    end

    test "excludes channels from other projects" do
      project = insert(:project)
      other_project = insert(:project)
      insert(:channel, project: project, name: "mine")
      insert(:channel, project: other_project, name: "theirs")

      results = Channels.list_channels_for_project_with_stats(project.id)

      assert length(results) == 1
      assert hd(results).channel.name == "mine"
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

  describe "create_channel/2" do
    setup do
      %{user: insert(:user)}
    end

    test "creates a channel with valid attrs and records audit event", %{
      user: user
    } do
      project = insert(:project)

      assert {:ok, %Channel{} = channel} =
               Channels.create_channel(
                 %{
                   name: "my-channel",
                   sink_url: "https://example.com/sink",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{
               name: "my-channel",
               enabled: true,
               lock_version: 1
             } = channel

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where: a.item_id == ^channel.id and a.item_type == "channel"
               )

      assert %{event: "created", actor_id: actor_id} = audit
      assert actor_id == user.id
    end

    test "returns error on missing required fields", %{user: user} do
      assert {:error, changeset} =
               Channels.create_channel(%{}, actor: user)

      assert %{name: _, sink_url: _, project_id: _} = errors_on(changeset)
    end

    test "returns error for non-URL sink_url", %{user: user} do
      project = insert(:project)

      assert {:error, changeset} =
               Channels.create_channel(
                 %{
                   name: "bad-sink",
                   sink_url: "not a url",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{sink_url: ["must be a valid URL"]} = errors_on(changeset)
    end

    test "returns error for non-http scheme sink_url", %{user: user} do
      project = insert(:project)

      assert {:error, changeset} =
               Channels.create_channel(
                 %{
                   name: "ftp-sink",
                   sink_url: "ftp://example.com",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{sink_url: ["must be either a http or https URL"]} =
               errors_on(changeset)
    end

    test "accepts valid http and https sink_urls", %{user: user} do
      project = insert(:project)

      assert {:ok, _} =
               Channels.create_channel(
                 %{
                   name: "http-sink",
                   sink_url: "http://example.com/path",
                   project_id: project.id
                 },
                 actor: user
               )

      assert {:ok, _} =
               Channels.create_channel(
                 %{
                   name: "https-sink",
                   sink_url: "https://example.com/path",
                   project_id: project.id
                 },
                 actor: user
               )
    end

    test "returns error on duplicate name within project", %{user: user} do
      channel = insert(:channel)

      assert {:error, changeset} =
               Channels.create_channel(
                 %{
                   name: channel.name,
                   sink_url: "https://example.com/other",
                   project_id: channel.project_id
                 },
                 actor: user
               )

      assert %{project_id: _} = errors_on(changeset)
    end
  end

  describe "update_channel/3" do
    setup do
      %{user: insert(:user)}
    end

    test "updates config fields, bumps lock_version, and records audit event",
         %{user: user} do
      channel = insert(:channel)

      assert {:ok, updated} =
               Channels.update_channel(channel, %{name: "new-name"}, actor: user)

      assert %{name: "new-name", lock_version: lock_version} = updated
      assert lock_version == channel.lock_version + 1

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel.id and a.item_type == "channel" and
                       a.event == "updated"
               )

      assert audit.actor_id == user.id
    end

    test "returns stale error on lock_version conflict", %{user: user} do
      channel = insert(:channel)

      # Simulate concurrent update by updating lock_version in DB
      {1, _} =
        Lightning.Repo.update_all(
          from(c in Channel, where: c.id == ^channel.id),
          set: [lock_version: channel.lock_version + 1]
        )

      assert {:error, changeset} =
               Channels.update_channel(channel, %{name: "stale-update"},
                 actor: user
               )

      assert changeset.errors[:lock_version]
    end
  end

  describe "delete_channel/2" do
    setup do
      %{user: insert(:user)}
    end

    test "deletes a channel with no snapshots and records audit event", %{
      user: user
    } do
      channel = insert(:channel)
      channel_id = channel.id

      assert {:ok, %Channel{}} = Channels.delete_channel(channel, actor: user)

      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(channel_id)
      end

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel_id and a.item_type == "channel" and
                       a.event == "deleted"
               )

      assert audit.actor_id == user.id
    end

    test "returns error when channel has snapshots", %{user: user} do
      channel = insert(:channel)
      insert(:channel_snapshot, channel: channel)

      assert {:error, changeset} = Channels.delete_channel(channel, actor: user)
      assert %{channel_snapshots: _} = errors_on(changeset)
    end
  end

  describe "get_channel_with_source_auth/1" do
    test "returns channel with preloaded source auth methods" do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "test-key"
                )
            )
          ]
        )

      result = Channels.get_channel_with_source_auth(channel.id)

      assert result.id == channel.id
      assert length(result.source_auth_methods) == 1

      [cam] = result.source_auth_methods
      assert cam.role == :source
      assert cam.webhook_auth_method.auth_type == :api
      assert cam.webhook_auth_method.api_key == "test-key"
    end

    test "returns channel with empty source_auth_methods when none configured" do
      channel = insert(:channel)

      result = Channels.get_channel_with_source_auth(channel.id)

      assert result.id == channel.id
      assert result.source_auth_methods == []
    end

    test "returns nil for non-existent channel" do
      assert Channels.get_channel_with_source_auth(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_channel_auth_methods/1" do
    test "returns empty list for a channel with no auth methods" do
      channel = insert(:channel)
      assert Channels.list_channel_auth_methods(channel) == []
    end

    test "returns preloaded source and sink records for a channel with both" do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      pc = insert(:project_credential, project: project)

      channel =
        insert(:channel,
          project: project,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method: wam
            ),
            build(:channel_auth_method,
              role: :sink,
              webhook_auth_method: nil,
              project_credential: pc
            )
          ]
        )

      cams = Channels.list_channel_auth_methods(channel)

      assert length(cams) == 2

      source = Enum.find(cams, &(&1.role == :source))
      sink = Enum.find(cams, &(&1.role == :sink))

      assert %ChannelAuthMethod{
               role: :source,
               webhook_auth_method_id: wam_id,
               webhook_auth_method: %{id: preloaded_wam_id}
             } = source

      assert wam_id == wam.id
      assert preloaded_wam_id == wam.id

      assert %ChannelAuthMethod{
               role: :sink,
               project_credential_id: pc_id,
               project_credential: %{id: preloaded_pc_id}
             } = sink

      assert pc_id == pc.id
      assert preloaded_pc_id == pc.id
    end
  end

  describe "get_or_create_current_snapshot/1" do
    setup do
      %{user: insert(:user)}
    end

    test "creates snapshot on first call" do
      channel = insert(:channel)

      assert {:ok, %ChannelSnapshot{} = snapshot} =
               Channels.get_or_create_current_snapshot(channel)

      assert snapshot.channel_id == channel.id
      assert snapshot.lock_version == channel.lock_version
      assert snapshot.name == channel.name
      assert snapshot.sink_url == channel.sink_url
      assert snapshot.enabled == channel.enabled
    end

    test "returns existing snapshot on same lock_version" do
      channel = insert(:channel)

      {:ok, snapshot1} = Channels.get_or_create_current_snapshot(channel)
      {:ok, snapshot2} = Channels.get_or_create_current_snapshot(channel)

      assert snapshot1.id == snapshot2.id
    end

    test "creates new snapshot on different lock_version", %{user: user} do
      channel = insert(:channel)
      {:ok, snapshot1} = Channels.get_or_create_current_snapshot(channel)

      {:ok, updated} =
        Channels.update_channel(channel, %{name: "updated-name"}, actor: user)

      {:ok, snapshot2} = Channels.get_or_create_current_snapshot(updated)

      assert snapshot1.id != snapshot2.id
      assert snapshot2.lock_version == updated.lock_version
      assert snapshot2.name == "updated-name"
    end
  end
end
