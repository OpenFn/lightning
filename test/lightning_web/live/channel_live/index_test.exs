defmodule LightningWeb.ChannelLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Auditing.Audit
  alias Lightning.Channels
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Repo

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  # The page is drawn by React from data-props; the texts it renders (the
  # empty state, the stat card titles, the delete confirmation) are tested in
  # the design system and in assets/test/design-system/ChannelsIndexPage.test.tsx.
  @page "#channels-index-page"

  defp props(view), do: page_props(view, @page)
  defp channel_names(view), do: Enum.map(props(view)["channels"], & &1["name"])

  defp row(view, channel),
    do: Enum.find(props(view)["channels"], &(&1["id"] == channel.id))

  defp toggle(view, channel, state),
    do:
      push_page_event(view, @page, "toggle_channel_state", %{
        "channel_state" => state,
        "value_key" => channel.id
      })

  defp delete_channel(view, channel),
    do: push_page_event(view, @page, "delete_channel", %{"id" => channel.id})

  describe "access control" do
    test "redirects unauthenticated users to login", %{project: project} do
      conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/projects/#{project.id}/channels")
    end

    test "renders the channels index for a project member", %{
      conn: conn,
      project: project
    } do
      insert(:channel, project: project, name: "my-channel")

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert html =~ "Channels"
      assert channel_names(view) == ["my-channel"]
    end

    @tag role: :viewer
    test "New Channel button is disabled for viewer role", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{"canCreateChannel" => false} = props(view)
    end

    @tag role: :editor
    test "New Channel button is enabled for editor role", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{"canCreateChannel" => true} = props(view)
    end
  end

  describe "channel metrics" do
    test "sends the Total Channels and Total Requests figures with the logs link",
         %{conn: conn, project: project} do
      insert(:channel, project: project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{
               "totalChannels" => 1,
               "totalRequests" => 0,
               "logsHref" => logs_href
             } = props(view)

      assert logs_href == ~p"/projects/#{project.id}/history/channels"
    end
  end

  describe "channel list rendering" do
    test "sends an empty list when the project has no channels", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{"channels" => [], "form" => nil} = props(view)
    end

    test "sends each channel's columns, with no last activity when it has no requests",
         %{conn: conn, project: project} do
      channel =
        insert(:channel,
          project: project,
          name: "test-channel",
          destination_url: "https://destination.example.com/data"
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{
               "name" => "test-channel",
               "enabled" => true,
               "destinationUrl" => "https://destination.example.com/data",
               "proxyUrl" => proxy_url,
               "requestCount" => 0,
               "lastActivityAt" => nil,
               "logsHref" => logs_href
             } = row(view, channel)

      assert proxy_url == "#{LightningWeb.Endpoint.url()}/channels/#{channel.id}"

      assert logs_href =~
               ~p"/projects/#{project.id}/history/channels?filters[channel_id]=#{channel.id}"
    end

    test "sends the request count and last activity when requests exist", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project, name: "active-channel")
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)
      t1 = ~U[2025-03-01 10:00:00.000000Z]
      t2 = ~U[2025-03-05 14:30:00.000000Z]

      Repo.insert!(%ChannelRequest{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-lv-1",
        state: :success,
        started_at: t1
      })

      Repo.insert!(%ChannelRequest{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-lv-2",
        state: :success,
        started_at: t2
      })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{"requestCount" => 2, "lastActivityAt" => last_at} =
               row(view, channel)

      assert last_at =~ "2025-03-05T14:30:00"
      assert %{"totalRequests" => 2} = props(view)
    end

    test "does not show channels from other projects", %{
      conn: conn,
      project: project
    } do
      insert(:channel, project: project, name: "mine")
      other_project = insert(:project)
      insert(:channel, project: other_project, name: "theirs")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert channel_names(view) == ["mine"]
    end
  end

  describe "toggle channel enabled state" do
    @tag role: :editor
    test "toggling a channel updates it, shows flash, and records audit event",
         %{
           conn: conn,
           project: project,
           user: user
         } do
      channel =
        insert(:channel, project: project, name: "toggle-me", enabled: true)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{"enabled" => true} = row(view, channel)

      assert toggle(view, channel, "false") =~ "Channel updated"

      updated = Channels.get_channel!(channel.id)
      assert updated.enabled == false
      assert %{"enabled" => false} = row(view, channel)

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel.id and
                       a.item_type == "channel" and
                       a.event == "updated"
               )

      assert audit.actor_id == user.id
    end

    @tag role: :editor
    test "can re-enable a disabled channel", %{
      conn: conn,
      project: project
    } do
      channel =
        insert(:channel,
          project: project,
          name: "disabled-one",
          enabled: false
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      toggle(view, channel, "true")

      assert Channels.get_channel!(channel.id).enabled == true
    end

    @tag role: :viewer
    test "a viewer's crafted toggle is refused", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project, name: "c", enabled: true)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{"canEditChannel" => false} = props(view)

      assert toggle(view, channel, "false") =~
               "You are not authorized to perform this action."

      assert Channels.get_channel!(channel.id).enabled == true
    end

    @tag role: :editor
    test "a toggle for another project's channel is refused", %{
      conn: conn,
      project: project
    } do
      theirs = insert(:channel, project: insert(:project), enabled: true)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert toggle(view, theirs, "false") =~ "Channel not found"
      assert Channels.get_channel!(theirs.id).enabled == true
    end
  end

  describe "delete channel" do
    @tag role: :viewer
    test "Edit and Delete are withheld from the viewer role, and a crafted delete is refused",
         %{conn: conn, project: project} do
      channel = insert(:channel, project: project, name: "viewer-channel")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert %{"canEditChannel" => false, "canDeleteChannel" => false} =
               props(view)

      assert delete_channel(view, channel) =~
               "You are not authorized to perform this action."

      assert Channels.get_channel!(channel.id)
    end

    @tag role: :editor
    test "deleting a channel removes it, shows flash, and records audit event",
         %{
           conn: conn,
           project: project,
           user: user
         } do
      channel =
        insert(:channel, project: project, name: "delete-me")

      channel_id = channel.id

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert row(view, channel)

      html = delete_channel(view, channel)

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      assert html =~ "Channel deleted."
      refute row(view, channel)

      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(channel.id)
      end

      # Audit event was recorded with the correct actor
      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel_id and
                       a.item_type == "channel" and
                       a.event == "deleted"
               )

      assert audit.actor_id == user.id
    end

    @tag role: :editor
    test "a delete for another project's channel is refused", %{
      conn: conn,
      project: project
    } do
      theirs = insert(:channel, project: insert(:project))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert delete_channel(view, theirs) =~ "Channel not found"
      assert Channels.get_channel!(theirs.id)
    end
  end
end
