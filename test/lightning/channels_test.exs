defmodule Lightning.ChannelsTest do
  use Lightning.DataCase, async: true

  import Ecto.Query

  alias Lightning.Auditing.Audit
  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelSnapshot

  describe "list_channels_for_project/1" do
    test "returns channels ordered by name, excluding other projects" do
      project = insert(:project)
      empty_project = insert(:project)
      insert(:channel, project: project, name: "bravo")
      insert(:channel, project: project, name: "alpha")
      insert(:channel, project: build(:project), name: "other")

      channels = Channels.list_channels_for_project(project.id)

      assert length(channels) == 2
      assert [%Channel{name: "alpha"}, %Channel{name: "bravo"}] = channels

      assert Channels.list_channels_for_project(empty_project.id) == []
    end
  end

  describe "list_channels_for_project_with_stats/1" do
    test "returns empty list for project with no channels and excludes other projects" do
      project = insert(:project)
      other_project = insert(:project)
      insert(:channel, project: other_project, name: "theirs")

      assert Channels.list_channels_for_project_with_stats(project.id) == []
    end

    test "returns correct request_count and last_activity for a channel with requests" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      t1 = ~U[2025-01-01 10:00:00.000000Z]
      t2 = ~U[2025-01-02 12:00:00.000000Z]

      insert(:channel_request,
        channel: channel,
        channel_snapshot: snapshot,
        state: :success,
        started_at: t1
      )

      insert(:channel_request,
        channel: channel,
        channel_snapshot: snapshot,
        state: :success,
        started_at: t2
      )

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

    test "returns multiple channels ordered by name with independent stats" do
      project = insert(:project)
      channel_b = insert(:channel, project: project, name: "bravo")
      channel_a = insert(:channel, project: project, name: "alpha")

      {:ok, snapshot_b} = Channels.get_or_create_current_snapshot(channel_b)

      insert(:channel_request,
        channel: channel_b,
        channel_snapshot: snapshot_b,
        state: :success,
        started_at: ~U[2025-06-01 00:00:00.000000Z]
      )

      results = Channels.list_channels_for_project_with_stats(project.id)

      assert [
               %{channel: %Channel{name: "alpha"}, request_count: 0},
               %{channel: %Channel{name: "bravo"}, request_count: 1}
             ] = results

      assert Enum.find(results, &(&1.channel.id == channel_a.id)).last_activity ==
               nil
    end
  end

  describe "get_channel!/1" do
    test "returns the channel and raises on not found" do
      channel = insert(:channel)
      assert Channels.get_channel!(channel.id).id == channel.id

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
                   destination_url: "https://example.com/destination",
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

    test "validates required fields, destination_url format, and name uniqueness",
         %{user: user} do
      # Missing required fields
      assert {:error, changeset} =
               Channels.create_channel(%{}, actor: user)

      assert %{name: _, destination_url: _, project_id: _} = errors_on(changeset)

      project = insert(:project)

      # Not a URL at all
      assert {:error, cs1} =
               Channels.create_channel(
                 %{
                   name: "bad",
                   destination_url: "not a url",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{destination_url: ["must be a valid URL"]} = errors_on(cs1)

      # Non-http scheme
      assert {:error, cs2} =
               Channels.create_channel(
                 %{
                   name: "ftp",
                   destination_url: "ftp://example.com",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{destination_url: ["must be either a http or https URL"]} =
               errors_on(cs2)

      # Valid http and https
      assert {:ok, _} =
               Channels.create_channel(
                 %{
                   name: "http-ok",
                   destination_url: "http://example.com/path",
                   project_id: project.id
                 },
                 actor: user
               )

      assert {:ok, ch} =
               Channels.create_channel(
                 %{
                   name: "https-ok",
                   destination_url: "https://example.com/path",
                   project_id: project.id
                 },
                 actor: user
               )

      # Duplicate name within project
      assert {:error, cs3} =
               Channels.create_channel(
                 %{
                   name: ch.name,
                   destination_url: "https://example.com/other",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{name: ["A channel with this name already exists in this project"]} =
               errors_on(cs3)
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

    test "returns {:ok, channel} when submitted with no real changes", %{
      user: user
    } do
      channel = insert(:channel)

      # Pass back the current values — empty changes map. Previously this
      # crashed with FunctionClauseError because Audit.event/4 returned
      # :no_changes and that was piped into Multi.insert/3.
      assert {:ok, unchanged} =
               Channels.update_channel(
                 channel,
                 %{name: channel.name, destination_url: channel.destination_url},
                 actor: user
               )

      assert unchanged.id == channel.id
      assert unchanged.lock_version == channel.lock_version

      # No audit row was written for the no-op save
      assert [] ==
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel.id and a.item_type == "channel" and
                       a.event == "updated"
               )
    end

    test "passing nil for destination_auth_method removes the join record",
         %{user: user} do
      project = insert(:project)
      pc = insert(:project_credential, project: project)
      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        role: :destination,
        webhook_auth_method: nil,
        project_credential: pc
      )

      channel =
        Channels.get_channel!(channel.id, include: [:destination_auth_method])

      assert channel.destination_auth_method != nil

      assert {:ok, updated} =
               Channels.update_channel(
                 channel,
                 %{"destination_auth_method" => nil},
                 actor: user
               )

      reloaded =
        Channels.get_channel!(updated.id,
          include: [:destination_auth_method]
        )

      assert reloaded.destination_auth_method == nil
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

    test "deletes a channel, cascade deletes snapshots, and records audit event",
         %{user: user} do
      channel = insert(:channel)
      snapshot = insert(:channel_snapshot, channel: channel)
      channel_id = channel.id

      assert {:ok, %Channel{}} = Channels.delete_channel(channel, actor: user)

      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(channel_id)
      end

      refute Repo.get(ChannelSnapshot, snapshot.id)

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel_id and a.item_type == "channel" and
                       a.event == "deleted"
               )

      assert audit.actor_id == user.id
    end
  end

  describe "get_channel_with_auth/1" do
    test "returns channel with preloaded client auth methods" do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :client,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "test-key"
                )
            )
          ]
        )

      result = Channels.get_channel_with_auth(channel.id)

      assert result.id == channel.id
      assert length(result.client_auth_methods) == 1

      [cam] = result.client_auth_methods
      assert cam.role == :client
      assert cam.webhook_auth_method.auth_type == :api
      assert cam.webhook_auth_method.api_key == "test-key"
    end

    test "returns channel with preloaded destination auth method" do
      project = insert(:project)
      pc = insert(:project_credential, project: project)

      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        webhook_auth_method: nil,
        project_credential: pc,
        role: :destination
      )

      result = Channels.get_channel_with_auth(channel.id)

      assert result.destination_auth_method.role == :destination
      assert result.destination_auth_method.project_credential.id == pc.id
    end

    test "returns empty auth methods when none configured and nil for non-existent" do
      channel = insert(:channel)

      result = Channels.get_channel_with_auth(channel.id)

      assert result.id == channel.id
      assert result.client_auth_methods == []
      assert result.destination_auth_method == nil

      assert Channels.get_channel_with_auth(Ecto.UUID.generate()) == nil
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
      assert snapshot.destination_url == channel.destination_url
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

  describe "get_channel_request_for_project/2" do
    test "returns channel request with preloads when project matches" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          state: :success,
          started_at: DateTime.utc_now()
        )

      event =
        insert(:channel_event,
          channel_request: request,
          request_path: "/test",
          latency_us: 100_000
        )

      result = Channels.get_channel_request_for_project(project.id, request.id)

      assert result.id == request.id
      assert result.channel.id == channel.id
      assert result.channel_snapshot.id == snapshot.id

      assert length(result.channel_events) == 1
      assert hd(result.channel_events).id == event.id
    end

    test "returns nil when channel request belongs to a different project" do
      project_a = insert(:project)
      project_b = insert(:project)
      channel = insert(:channel, project: project_a)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          state: :success,
          started_at: DateTime.utc_now()
        )

      assert Channels.get_channel_request_for_project(project_b.id, request.id) ==
               nil
    end

    test "returns nil for non-existent request ID" do
      project = insert(:project)

      assert Channels.get_channel_request_for_project(
               project.id,
               Ecto.UUID.generate()
             ) == nil
    end

    test "returns nil for invalid UUID" do
      project = insert(:project)

      assert Channels.get_channel_request_for_project(
               project.id,
               "not-a-valid-uuid"
             ) == nil
    end
  end
end
