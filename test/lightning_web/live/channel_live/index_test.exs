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

  describe "channel metrics" do
    test "shows Total Channels and Total Requests stat cards", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert html =~ "Total Channels"
      assert html =~ "Total Requests"
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
          destination_url: "https://destination.example.com/data"
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert has_element?(view, "tr#channel-#{channel.id}")

      html = render(view)

      assert html =~ "test-channel"
      assert html =~ "https://destination.example.com/data"
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
          destination_url: "https://example.com/destination"
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
    test "submitting with a client auth method saves the association", %{
      conn: conn,
      project: project
    } do
      wam = insert(:webhook_auth_method, project: project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      view
      |> form("#channel-form-new",
        channel: %{
          name: "channel-with-auth",
          destination_url: "https://example.com/destination",
          client_auth_methods: %{wam.id => "true"}
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      channel =
        Channels.list_channels_for_project(project.id)
        |> Enum.find(&(&1.name == "channel-with-auth"))

      assert channel

      channel = Repo.preload(channel, :channel_auth_methods)

      assert [%{role: :client, webhook_auth_method_id: wam_id}] =
               channel.channel_auth_methods

      assert wam_id == wam.id
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
        |> form("##{form_id}", channel: %{name: "", destination_url: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    @tag role: :editor
    test "submitting with a duplicate name shows inline validation error", %{
      conn: conn,
      project: project
    } do
      channel =
        insert(:channel,
          project: project,
          name: "existing",
          destination_url: "https://old.example.com"
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      form_id = "channel-form-new"

      html =
        view
        |> form("##{form_id}",
          channel: %{name: channel.name, destination_url: "https://example.com"}
        )
        |> render_submit()

      assert html =~ "A channel with this name already exists in this project"
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

  describe "form structure" do
    @tag role: :editor
    test "renders fields in the correct order with labels, sublabels, and placeholder",
         %{conn: conn, project: project} do
      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      # Fields appear in this order: Name, Destination URL, Destination Credential,
      # Enabled, Client Credentials
      name_pos = :binary.match(html, "Name") |> elem(0)
      dest_url_pos = :binary.match(html, "Destination URL") |> elem(0)
      dest_cred_pos = :binary.match(html, "Destination Credential") |> elem(0)
      enabled_pos = :binary.match(html, "Enabled") |> elem(0)
      client_cred_pos = :binary.match(html, "Client Credentials") |> elem(0)

      assert name_pos < dest_url_pos
      assert dest_url_pos < dest_cred_pos
      assert dest_cred_pos < enabled_pos
      assert enabled_pos < client_cred_pos

      # Sublabels
      assert html =~ "The service OpenFn will forward requests to"
      assert html =~ "How OpenFn authenticates with the destination service"
      assert html =~ "Credentials that you can use to access this channel"

      # Destination URL placeholder
      assert has_element?(
               view,
               "input[name='channel[destination_url]'][placeholder='https://']"
             )
    end

    @tag role: :editor
    test "Destination Credential is a select dropdown with None plus project credentials",
         %{conn: conn, project: project, user: user} do
      cred1 =
        insert(:credential, project: project, user: user, name: "My API Key")

      _pc1 = insert(:project_credential, project: project, credential: cred1)

      cred2 =
        insert(:credential, project: project, user: user, name: "OAuth Token")

      _pc2 = insert(:project_credential, project: project, credential: cred2)

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      # Renders as a <select>, not checkboxes
      assert has_element?(
               view,
               "select[name='channel[destination_credential_id]']"
             )

      refute has_element?(
               view,
               "input[type='checkbox'][id^='destination_auth_']"
             )

      # "None" is the first option, credentials follow
      assert has_element?(view, "select option[value='']", "None")
      assert html =~ "My API Key"
      assert html =~ "OAuth Token"
    end

    @tag role: :editor
    test "Client Credentials still renders as multi-select checkboxes", %{
      conn: conn,
      project: project
    } do
      wam1 = insert(:webhook_auth_method, project: project, name: "API Key Auth")
      wam2 = insert(:webhook_auth_method, project: project, name: "Basic Auth")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      assert has_element?(view, "input[type='checkbox']#client_auth_#{wam1.id}")
      assert has_element?(view, "input[type='checkbox']#client_auth_#{wam2.id}")
      assert has_element?(view, "label", "API Key Auth")
      assert has_element?(view, "label", "Basic Auth")
    end

    @tag role: :editor
    test "shows Add New links for client credentials and destination credential",
         %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      assert html =~ "/settings#webhook_security"
      assert html =~ "/settings#credentials"
      assert html =~ "Add New"
      refute html =~ "Create a new one in project settings."
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
          destination_url: "https://old.example.com"
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
          destination_url: "https://old.example.com"
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      form_id = "channel-form-#{channel.id}"

      view
      |> form("##{form_id}",
        channel: %{
          name: "updated-name",
          destination_url: "https://new.example.com"
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      html = render(view)
      assert html =~ "Channel updated successfully"
      assert html =~ "updated-name"

      updated = Channels.get_channel!(channel.id)
      assert updated.name == "updated-name"
    end

    @tag role: :editor
    test "edit form shows available auth methods and credentials", %{
      conn: conn,
      project: project,
      user: user
    } do
      wam = insert(:webhook_auth_method, project: project)
      credential = insert(:credential, project: project, user: user)
      _pc = insert(:project_credential, project: project, credential: credential)
      channel = insert(:channel, project: project)

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      assert html =~ wam.name
      assert html =~ credential.name
    end

    @tag role: :editor
    test "pre-selects existing client checkbox and destination dropdown", %{
      conn: conn,
      project: project,
      user: user
    } do
      wam = insert(:webhook_auth_method, project: project)
      credential = insert(:credential, project: project, user: user)
      pc = insert(:project_credential, project: project, credential: credential)

      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        role: :client,
        webhook_auth_method: wam
      )

      insert(:channel_auth_method,
        channel: channel,
        role: :destination,
        webhook_auth_method: nil,
        project_credential: pc
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      # Client auth method is checked
      assert has_element?(view, "#client_auth_#{wam.id}[value='true']")

      # Destination credential is selected in the dropdown
      assert has_element?(
               view,
               "select[name='channel[destination_credential_id]'] option[value='#{pc.id}'][selected]"
             )
    end

    @tag role: :editor
    test "saving can remove a client auth, keep destination, and add a new client in one save",
         %{conn: conn, project: project, user: user} do
      wam1 = insert(:webhook_auth_method, project: project)
      wam2 = insert(:webhook_auth_method, project: project)
      credential = insert(:credential, project: project, user: user)
      pc = insert(:project_credential, project: project, credential: credential)

      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        role: :client,
        webhook_auth_method: wam1
      )

      insert(:channel_auth_method,
        channel: channel,
        role: :destination,
        webhook_auth_method: nil,
        project_credential: pc
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      # Remove wam1, add wam2, keep destination credential via dropdown
      view
      |> form("#channel-form-#{channel.id}",
        channel: %{
          name: channel.name,
          client_auth_methods: %{wam1.id => "false", wam2.id => "true"},
          destination_credential_id: pc.id
        }
      )
      |> render_change()

      view
      |> form("#channel-form-#{channel.id}")
      |> render_submit()

      updated =
        Channels.get_channel!(channel.id, include: [:channel_auth_methods])

      client_cams =
        Enum.filter(updated.channel_auth_methods, &(&1.role == :client))

      destination_cams =
        Enum.filter(updated.channel_auth_methods, &(&1.role == :destination))

      assert length(client_cams) == 1
      assert hd(client_cams).webhook_auth_method_id == wam2.id

      assert length(destination_cams) == 1
      assert hd(destination_cams).project_credential_id == pc.id
    end
  end

  describe "destination credential round-trips" do
    @tag role: :editor
    test "creating a channel with a destination credential saves the auth method",
         %{conn: conn, project: project, user: user} do
      credential = insert(:credential, project: project, user: user)
      pc = insert(:project_credential, project: project, credential: credential)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      view
      |> form("#channel-form-new",
        channel: %{
          name: "with-dest-cred",
          destination_url: "https://example.com/api",
          destination_credential_id: pc.id
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")
      assert render(view) =~ "Channel created successfully"

      channel =
        Channels.list_channels_for_project(project.id)
        |> Enum.find(&(&1.name == "with-dest-cred"))

      assert channel

      loaded =
        Channels.get_channel!(channel.id, include: [:channel_auth_methods])

      dest_cams =
        Enum.filter(loaded.channel_auth_methods, &(&1.role == :destination))

      assert length(dest_cams) == 1
      assert hd(dest_cams).project_credential_id == pc.id
    end

    @tag role: :editor
    test "creating a channel with None destination credential saves no auth method",
         %{conn: conn, project: project, user: user} do
      credential = insert(:credential, project: project, user: user)
      _pc = insert(:project_credential, project: project, credential: credential)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      # Select "None" (empty value) in the destination credential dropdown
      view
      |> form("#channel-form-new",
        channel: %{
          name: "no-dest-cred",
          destination_url: "https://example.com/api",
          destination_credential_id: ""
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      channel =
        Channels.list_channels_for_project(project.id)
        |> Enum.find(&(&1.name == "no-dest-cred"))

      assert channel

      loaded =
        Channels.get_channel!(channel.id, include: [:channel_auth_methods])

      dest_cams =
        Enum.filter(loaded.channel_auth_methods, &(&1.role == :destination))

      assert dest_cams == []
    end

    @tag role: :editor
    test "changing destination credential from one to another swaps the auth method",
         %{conn: conn, project: project, user: user} do
      cred1 = insert(:credential, project: project, user: user, name: "Cred A")
      pc1 = insert(:project_credential, project: project, credential: cred1)

      cred2 = insert(:credential, project: project, user: user, name: "Cred B")
      pc2 = insert(:project_credential, project: project, credential: cred2)

      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        role: :destination,
        webhook_auth_method: nil,
        project_credential: pc1
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      # Swap from pc1 to pc2 via the dropdown
      view
      |> form("#channel-form-#{channel.id}",
        channel: %{destination_credential_id: pc2.id}
      )
      |> render_change()

      view
      |> form("#channel-form-#{channel.id}")
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      loaded =
        Channels.get_channel!(channel.id, include: [:channel_auth_methods])

      dest_cams =
        Enum.filter(loaded.channel_auth_methods, &(&1.role == :destination))

      assert length(dest_cams) == 1
      assert hd(dest_cams).project_credential_id == pc2.id
    end

    @tag role: :editor
    test "selecting None removes an existing destination auth method",
         %{conn: conn, project: project, user: user} do
      credential = insert(:credential, project: project, user: user)
      pc = insert(:project_credential, project: project, credential: credential)

      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        role: :destination,
        webhook_auth_method: nil,
        project_credential: pc
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      # Select "None" (empty value)
      view
      |> form("#channel-form-#{channel.id}",
        channel: %{destination_credential_id: ""}
      )
      |> render_change()

      view
      |> form("#channel-form-#{channel.id}")
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      loaded =
        Channels.get_channel!(channel.id, include: [:channel_auth_methods])

      dest_cams =
        Enum.filter(loaded.channel_auth_methods, &(&1.role == :destination))

      assert dest_cams == []
    end
  end

  describe "delete channel" do
    @tag role: :editor
    test "delete button uses data-confirm attribute (not phx-confirm)", %{
      conn: conn,
      project: project
    } do
      _channel = insert(:channel, project: project, name: "confirm-me")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      assert has_element?(
               view,
               "[phx-click='delete_channel'][data-confirm]"
             )

      refute has_element?(
               view,
               "[phx-click='delete_channel'][phx-confirm]"
             )
    end

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
