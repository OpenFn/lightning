defmodule Lightning.Channels.ChannelRequestsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Channels.ChannelSnapshot
  alias Lightning.Channels.SearchParams

  describe "list_channel_requests/3" do
    setup do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      %{project: project, channel: channel, snapshot: snapshot}
    end

    defp insert_request(channel, snapshot, attrs \\ []) do
      insert(
        :channel_request,
        [channel: channel, channel_snapshot: snapshot, state: :success] ++ attrs
      )
    end

    defp insert_event(request, attrs) do
      insert(:channel_event, [channel_request: request] ++ attrs)
    end

    test "returns a Scrivener.Page scoped to the given project, excluding other projects",
         %{
           project: project,
           channel: channel,
           snapshot: snapshot
         } do
      _mine = insert_request(channel, snapshot)
      other_channel = insert(:channel)

      {:ok, other_snapshot} =
        Channels.get_or_create_current_snapshot(other_channel)

      _theirs = insert_request(other_channel, other_snapshot)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert %Scrivener.Page{entries: [%ChannelRequest{}]} = page
      assert page.total_entries == 1
      assert hd(page.entries).channel_id == channel.id
    end

    test "filters by channel_id when provided", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      channel_b = insert(:channel, project: project)
      {:ok, snapshot_b} = Channels.get_or_create_current_snapshot(channel_b)

      insert_request(channel, snapshot)
      insert_request(channel_b, snapshot_b)

      params = SearchParams.new(%{"channel_id" => channel.id})
      page = Channels.list_channel_requests(project, params)

      assert page.total_entries == 1
      assert hd(page.entries).channel_id == channel.id
    end

    test "returns all project requests when no channel_id filter", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      channel_b = insert(:channel, project: project)
      {:ok, snapshot_b} = Channels.get_or_create_current_snapshot(channel_b)

      insert_request(channel, snapshot)
      insert_request(channel_b, snapshot_b)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert page.total_entries == 2
    end

    test "preloads :channel association on each entry", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      insert_request(channel, snapshot)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert [%ChannelRequest{channel: %Channel{id: channel_id}}] = page.entries
      assert channel_id == channel.id
    end

    test "preloads :channel_events with only :destination_response and :error types",
         %{project: project, channel: channel, snapshot: snapshot} do
      request = insert_request(channel, snapshot)

      insert_event(request,
        type: :destination_response,
        request_path: "/outbound"
      )

      insert_event(request, type: :error, error_message: "timeout")

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      [entry] = page.entries

      assert length(entry.channel_events) == 2

      assert Enum.all?(
               entry.channel_events,
               &(&1.type in [:destination_response, :error])
             )

      destination_event =
        Enum.find(entry.channel_events, &(&1.type == :destination_response))

      error_event = Enum.find(entry.channel_events, &(&1.type == :error))

      assert %{request_path: "/outbound"} = destination_event
      assert %{error_message: "timeout"} = error_event
    end

    test "entries are ordered by started_at descending", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      t1 = ~U[2025-01-01 10:00:00.000000Z]
      t2 = ~U[2025-01-02 10:00:00.000000Z]

      insert_request(channel, snapshot, started_at: t1)
      insert_request(channel, snapshot, started_at: t2)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert [first, second] = page.entries
      assert first.started_at == t2
      assert second.started_at == t1
    end
  end

  describe "delete_expired_requests/2" do
    test "deletes expired requests, preserves recent, and cascades to events" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      # First verify no-op when nothing is expired
      assert :ok = Channels.delete_expired_requests(project.id, 7)

      old_request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          started_at: Lightning.current_time() |> Timex.shift(days: -8)
        )

      recent_request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          started_at: Lightning.current_time() |> Timex.shift(days: -6)
        )

      old_event =
        insert(:channel_event,
          channel_request: old_request,
          type: :destination_response
        )

      recent_event =
        insert(:channel_event,
          channel_request: recent_request,
          type: :destination_response
        )

      assert :ok = Channels.delete_expired_requests(project.id, 7)

      # Old request and its event are deleted
      refute Repo.get(ChannelRequest, old_request.id)
      refute Repo.get(ChannelEvent, old_event.id)

      # Recent request and its event are preserved
      assert Repo.get(ChannelRequest, recent_request.id)
      assert Repo.get(ChannelEvent, recent_event.id)
    end

    test "cleans up orphaned channel_snapshots" do
      user = insert(:user)
      project = insert(:project)
      channel = insert(:channel, project: project)

      {:ok, old_snapshot} =
        Channels.get_or_create_current_snapshot(channel)

      {:ok, updated_channel} =
        Channels.update_channel(channel, %{name: "updated"}, actor: user)

      {:ok, current_snapshot} =
        Channels.get_or_create_current_snapshot(updated_channel)

      # Old request referencing the old snapshot
      insert(:channel_request,
        channel: channel,
        channel_snapshot: old_snapshot,
        started_at: Lightning.current_time() |> Timex.shift(days: -8)
      )

      # Recent request referencing the current snapshot
      insert(:channel_request,
        channel: channel,
        channel_snapshot: current_snapshot,
        started_at: Lightning.current_time() |> Timex.shift(days: -6)
      )

      assert :ok = Channels.delete_expired_requests(project.id, 7)

      # Old snapshot is orphaned (no remaining requests, lock_version
      # doesn't match channel) and should be deleted
      refute Repo.get(ChannelSnapshot, old_snapshot.id)

      # Current snapshot still has a request and matches lock_version
      assert Repo.get(ChannelSnapshot, current_snapshot.id)
    end

    test "preserves snapshots still referenced by non-expired requests" do
      user = insert(:user)
      project = insert(:project)
      channel = insert(:channel, project: project)

      {:ok, old_snapshot} =
        Channels.get_or_create_current_snapshot(channel)

      {:ok, _updated_channel} =
        Channels.update_channel(channel, %{name: "updated"}, actor: user)

      # Recent request still references the old snapshot
      insert(:channel_request,
        channel: channel,
        channel_snapshot: old_snapshot,
        started_at: Lightning.current_time() |> Timex.shift(days: -6)
      )

      assert :ok = Channels.delete_expired_requests(project.id, 7)

      # Old snapshot is NOT deleted because a non-expired request
      # still references it
      assert Repo.get(ChannelSnapshot, old_snapshot.id)
    end
  end

  describe "delete_channel_requests_for_project/1" do
    test "deletes all channel requests for a project" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot
        )

      event =
        insert(:channel_event,
          channel_request: request,
          type: :destination_response
        )

      assert :ok =
               Channels.delete_channel_requests_for_project(
                 %Lightning.Projects.Project{id: project.id}
               )

      refute Repo.get(ChannelRequest, request.id)
      refute Repo.get(ChannelEvent, event.id)
    end
  end

  # ---------------------------------------------------------------
  # Phase 1a contract tests — client auth method tracking on requests
  # ---------------------------------------------------------------
  #
  # These tests define the target interface after:
  # - D3: client_webhook_auth_method_id and client_auth_type on channel_requests
  #
  # They will not compile/pass until Phase 1b implements the changes.

  describe "ChannelRequest changeset — auth method fields" do
    test "accepts client_webhook_auth_method_id and client_auth_type" do
      channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)
      auth_method = insert(:webhook_auth_method, project: channel.project)

      attrs = %{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-auth-test",
        state: :success,
        started_at: DateTime.utc_now(),
        client_webhook_auth_method_id: auth_method.id,
        client_auth_type: "api"
      }

      changeset = ChannelRequest.changeset(%ChannelRequest{}, attrs)
      assert changeset.valid?

      {:ok, request} = Repo.insert(changeset)
      assert request.client_webhook_auth_method_id == auth_method.id
      assert request.client_auth_type == "api"
    end

    test "auth method fields are nullable" do
      channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      attrs = %{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-no-auth",
        state: :success,
        started_at: DateTime.utc_now()
      }

      {:ok, request} =
        ChannelRequest.changeset(%ChannelRequest{}, attrs) |> Repo.insert()

      assert request.client_webhook_auth_method_id == nil
      assert request.client_auth_type == nil
    end

    test "belongs_to client_webhook_auth_method loads correctly" do
      channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)
      auth_method = insert(:webhook_auth_method, project: channel.project)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          client_webhook_auth_method_id: auth_method.id,
          client_auth_type: "basic"
        )

      loaded =
        ChannelRequest
        |> Repo.get!(request.id)
        |> Repo.preload(:client_webhook_auth_method)

      assert loaded.client_webhook_auth_method.id == auth_method.id
      assert loaded.client_auth_type == "basic"
    end
  end

  describe "client_webhook_auth_method_id nilification on delete" do
    test "FK is nilified when auth method is deleted, client_auth_type survives" do
      channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)
      auth_method = insert(:webhook_auth_method, project: channel.project)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          client_webhook_auth_method_id: auth_method.id,
          client_auth_type: "api"
        )

      # Verify FK is set
      assert Repo.get!(ChannelRequest, request.id).client_webhook_auth_method_id ==
               auth_method.id

      # Delete the auth method
      Repo.delete!(auth_method)

      # FK should be nilified by on_delete: :nilify_all
      reloaded = Repo.get!(ChannelRequest, request.id)
      assert reloaded.client_webhook_auth_method_id == nil

      # client_auth_type is a denormalized snapshot — it survives deletion
      assert reloaded.client_auth_type == "api"
    end
  end

  describe "delete_channel/2 with requests" do
    test "removes requests before deleting channel" do
      user = insert(:user)
      channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot
        )

      event =
        insert(:channel_event,
          channel_request: request,
          type: :destination_response
        )

      assert {:ok, %Channel{}} =
               Channels.delete_channel(channel, actor: user)

      refute Repo.get(Channel, channel.id)
      refute Repo.get(ChannelRequest, request.id)
      refute Repo.get(ChannelEvent, event.id)
      refute Repo.get(ChannelSnapshot, snapshot.id)
    end
  end
end
