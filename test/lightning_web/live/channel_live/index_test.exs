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

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels")

      assert html =~ "Channels"
      assert html =~ "my-channel"
    end

    @tag role: :viewer
    test "New Channel button is disabled for viewer role", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert has_element?(view, "#new-channel-button:disabled")
    end

    @tag role: :editor
    test "New Channel button is enabled for editor role", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      refute has_element?(view, "#new-channel-button:disabled")
      assert has_element?(view, "#new-channel-button")
    end
  end

  describe "channel list rendering" do
    test "shows empty state when project has no channels", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert html =~ "No channels found."
    end

    test "shows channel columns with zero requests and Never for last activity",
         %{
           conn: conn,
           project: project
         } do
      channel =
        insert(:channel,
          project: project,
          name: "test-channel",
          sink_url: "https://sink.example.com/data"
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert has_element?(view, "tr#channel-#{channel.id}")

      html = render(view)

      assert html =~ "test-channel"
      assert html =~ "https://sink.example.com/data"
      assert html =~ "Never"
    end

    test "shows request count and last activity when requests exist", %{
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

      html = render(view)

      assert html =~ "active-channel"
      assert html =~ "2"
      refute html =~ "Never"
    end

    test "does not show channels from other projects", %{
      conn: conn,
      project: project
    } do
      insert(:channel, project: project, name: "mine")
      other_project = insert(:project)
      insert(:channel, project: other_project, name: "theirs")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert html =~ "mine"
      refute html =~ "theirs"
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

      assert has_element?(view, "tr#channel-#{channel.id}")

      html =
        view
        |> element("#toggle-control-#{channel.id}")
        |> render_click()

      assert html =~ "Channel updated"

      updated = Channels.get_channel!(channel.id)
      assert updated.enabled == false

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel.id and a.item_type == "channel" and
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
        insert(:channel, project: project, name: "disabled-one", enabled: false)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      view
      |> element("#toggle-control-#{channel.id}")
      |> render_click()

      assert Channels.get_channel!(channel.id).enabled == true
    end
  end

  describe "new channel form" do
    @tag role: :editor
    test "navigating to /channels/new shows the form modal", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      assert html =~ "New Channel"
      assert has_element?(view, "#new-modal")
    end

    @tag role: :editor
    test "submitting valid params creates channel and shows success flash", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      form_id = "channel-form-new"

      view
      |> form("##{form_id}",
        channel: %{
          name: "new-channel",
          sink_url: "https://example.com/sink"
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      html = render(view)
      assert html =~ "Channel created successfully"
      assert html =~ "new-channel"

      assert Channels.list_channels_for_project(project.id)
             |> Enum.any?(&(&1.name == "new-channel"))
    end

    @tag role: :editor
    test "submitting with missing name shows inline validation error", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      form_id = "channel-form-new"

      html =
        view
        |> form("##{form_id}", channel: %{name: "", sink_url: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    @tag role: :viewer
    test "viewer is redirected when accessing /channels/new", %{
      conn: conn,
      project: project
    } do
      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/projects/#{project.id}/channels/new")

      assert redirect_to == ~p"/projects/#{project.id}/channels"
    end
  end

  describe "edit channel form" do
    @tag role: :editor
    test "/channels/:id/edit mounts form pre-populated with channel values", %{
      conn: conn,
      project: project
    } do
      channel =
        insert(:channel,
          project: project,
          name: "edit-me",
          sink_url: "https://old.example.com"
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      html = render(view)
      assert html =~ "Edit Channel"
      assert html =~ "edit-me"
      assert html =~ "https://old.example.com"
    end

    @tag role: :editor
    test "saving valid changes updates the channel and shows success flash", %{
      conn: conn,
      project: project
    } do
      channel =
        insert(:channel,
          project: project,
          name: "old-name",
          sink_url: "https://old.example.com"
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      form_id = "channel-form-#{channel.id}"

      view
      |> form("##{form_id}",
        channel: %{name: "updated-name", sink_url: "https://new.example.com"}
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      html = render(view)
      assert html =~ "Channel updated successfully"
      assert html =~ "updated-name"

      updated = Channels.get_channel!(channel.id)
      assert updated.name == "updated-name"
    end
  end

  describe "delete channel" do
    @tag role: :viewer
    test "Edit and Delete buttons are absent for viewer role", %{
      conn: conn,
      project: project
    } do
      channel = insert(:channel, project: project, name: "viewer-channel")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      refute has_element?(
               view,
               "[phx-click='delete_channel'][phx-value-id='#{channel.id}']"
             )

      refute has_element?(
               view,
               "a[patch$='/channels/#{channel.id}/edit']"
             )
    end

    @tag role: :editor
    test "deleting a channel removes it and shows success flash", %{
      conn: conn,
      project: project
    } do
      channel =
        insert(:channel, project: project, name: "delete-me")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert has_element?(view, "tr#channel-#{channel.id}")

      view
      |> element("[phx-click='delete_channel'][phx-value-id='#{channel.id}']")
      |> render_click()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      html = render(view)
      assert html =~ "Channel deleted."
      refute html =~ "delete-me"

      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(channel.id)
      end
    end

    @tag role: :editor
    test "successful delete records audit event with actor", %{
      conn: conn,
      project: project,
      user: user
    } do
      channel = insert(:channel, project: project, name: "audit-delete")
      channel_id = channel.id

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      view
      |> element("[phx-click='delete_channel'][phx-value-id='#{channel.id}']")
      |> render_click()

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
end
