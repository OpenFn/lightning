defmodule LightningWeb.ChannelLive.FormTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Channels
  alias Lightning.Repo

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  # The form is drawn by React from the page's `form` prop and saves with one
  # event. Its fields, the placeholder, the "None" option, the "Add New"
  # links, the browser-side required checks and how it shows the reply's
  # field errors are tested in the design system's ChannelsIndexPage.test.tsx.
  @page "#channels-index-page"

  defp props(view), do: page_props(view, @page)
  defp form(view), do: props(view)["form"]

  # What the page sends from its Save button: every field, as typed.
  defp save(view, values) do
    push_page_event(
      view,
      @page,
      "save_channel",
      Map.merge(
        %{
          "name" => "",
          "enabled" => true,
          "destinationUrl" => "",
          "destinationCredentialId" => "",
          "clientAuthMethodIds" => []
        },
        values
      )
    )
  end

  defp auth_methods(channel, role) do
    Channels.get_channel!(channel.id, include: [:channel_auth_methods]).channel_auth_methods
    |> Enum.filter(&(&1.role == role))
  end

  describe "new channel form" do
    @tag role: :editor
    test "navigating to /channels/new opens the form", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      assert html =~ "New Channel"

      assert %{
               "channel" => nil,
               "credentialOptions" => [],
               "authMethodOptions" => []
             } = form(view)
    end

    @tag role: :editor
    test "saving valid values creates the channel and shows the success flash",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      save(view, %{
        "name" => "new-channel",
        "destinationUrl" => "https://example.com/destination"
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      html = render(view)
      assert html =~ "Channel created successfully"
      assert %{"form" => nil} = props(view)
      assert Enum.any?(props(view)["channels"], &(&1["name"] == "new-channel"))

      assert Channels.list_channels_for_project(project.id)
             |> Enum.any?(&(&1.name == "new-channel"))
    end

    @tag role: :editor
    test "saving with a client auth method saves the association", %{
      conn: conn,
      project: project
    } do
      wam = insert(:webhook_auth_method, project: project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      save(view, %{
        "name" => "channel-with-auth",
        "destinationUrl" => "https://example.com/destination",
        "clientAuthMethodIds" => [wam.id]
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      channel =
        Channels.list_channels_for_project(project.id)
        |> Enum.find(&(&1.name == "channel-with-auth"))

      assert channel

      assert [%{role: :client, webhook_auth_method_id: wam_id}] =
               Repo.preload(channel, :channel_auth_methods).channel_auth_methods

      assert wam_id == wam.id
    end

    @tag role: :editor
    test "saving with a missing name and URL replies with the field errors", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      save(view, %{"name" => "", "destinationUrl" => ""})

      # The kit's wording for a blank field (reply_error/2 translates the
      # changeset); the page's own check says "can't be blank" before a save.
      assert_reply(view, %{
        error: "Please fix the errors below.",
        fieldErrors: %{
          "name" => ["This field can't be blank."],
          "destinationUrl" => ["This field can't be blank."]
        }
      })

      # The form stays open.
      assert form(view)
      assert Channels.list_channels_for_project(project.id) == []
    end

    @tag role: :editor
    test "saving with a duplicate name replies with the name's error", %{
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

      save(view, %{
        "name" => channel.name,
        "destinationUrl" => "https://example.com"
      })

      assert_reply(view, %{
        fieldErrors: %{
          "name" => ["A channel with this name already exists in this project"]
        }
      })
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

    @tag role: :viewer
    test "a viewer's crafted save is refused", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      save(view, %{"name" => "sneaky", "destinationUrl" => "https://example.com"})

      assert_reply(view, %{
        error: "You are not authorized to perform this action."
      })

      assert Channels.list_channels_for_project(project.id) == []
    end

    @tag role: :editor
    test "a save with no form open is refused", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      save(view, %{"name" => "stray", "destinationUrl" => "https://example.com"})

      assert_reply(view, %{
        error: "You are not authorized to perform this action."
      })

      assert Channels.list_channels_for_project(project.id) == []
    end
  end

  describe "form options" do
    @tag role: :editor
    test "offers the project's credentials for the destination, by name",
         %{conn: conn, project: project, user: user} do
      cred1 =
        insert(:credential, project: project, user: user, name: "My API Key")

      pc1 = insert(:project_credential, project: project, credential: cred1)

      cred2 =
        insert(:credential, project: project, user: user, name: "OAuth Token")

      pc2 = insert(:project_credential, project: project, credential: cred2)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      # Only the id and the name: nothing of the credential's body or owner.
      assert %{"credentialOptions" => options} = form(view)

      assert Enum.sort_by(options, & &1["name"]) == [
               %{"id" => pc1.id, "name" => "My API Key"},
               %{"id" => pc2.id, "name" => "OAuth Token"}
             ]
    end

    @tag role: :editor
    test "offers the project's webhook auth methods for the client credentials",
         %{conn: conn, project: project} do
      wam1 = insert(:webhook_auth_method, project: project, name: "API Key Auth")
      wam2 = insert(:webhook_auth_method, project: project, name: "Basic Auth")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      assert %{"authMethodOptions" => options} = form(view)

      assert Enum.sort_by(options, & &1["name"]) == [
               %{"id" => wam1.id, "name" => "API Key Auth"},
               %{"id" => wam2.id, "name" => "Basic Auth"}
             ]
    end
  end

  describe "edit channel form" do
    @tag role: :editor
    test "/channels/:id/edit opens the form with the channel's values and proxy URL",
         %{conn: conn, project: project} do
      channel =
        insert(:channel,
          project: project,
          name: "edit-me",
          destination_url: "https://old.example.com"
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      assert html =~ "Edit Channel"

      assert %{
               "channel" => %{
                 "id" => id,
                 "name" => "edit-me",
                 "enabled" => true,
                 "destinationUrl" => "https://old.example.com",
                 "destinationCredentialId" => "",
                 "clientAuthMethodIds" => [],
                 "proxyUrl" => proxy_url
               }
             } = form(view)

      assert id == channel.id
      assert proxy_url == "#{LightningWeb.Endpoint.url()}/channels/#{channel.id}"
    end

    @tag role: :editor
    test "saving valid changes updates the channel and shows the success flash",
         %{conn: conn, project: project} do
      channel =
        insert(:channel,
          project: project,
          name: "old-name",
          destination_url: "https://old.example.com"
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      save(view, %{
        "name" => "updated-name",
        "destinationUrl" => "https://new.example.com"
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      html = render(view)
      assert html =~ "Channel updated successfully"
      assert Enum.any?(props(view)["channels"], &(&1["name"] == "updated-name"))

      updated = Channels.get_channel!(channel.id)
      assert updated.name == "updated-name"
      assert updated.destination_url == "https://new.example.com"
    end

    @tag role: :editor
    test "the edit form offers the available auth methods and credentials", %{
      conn: conn,
      project: project,
      user: user
    } do
      wam = insert(:webhook_auth_method, project: project)
      credential = insert(:credential, project: project, user: user)
      _pc = insert(:project_credential, project: project, credential: credential)
      channel = insert(:channel, project: project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      assert %{"authMethodOptions" => [%{"name" => wam_name}]} = form(view)
      assert wam_name == wam.name
      assert %{"credentialOptions" => [%{"name" => cred_name}]} = form(view)
      assert cred_name == credential.name
    end

    @tag role: :editor
    test "pre-selects the existing client auth method and destination credential",
         %{conn: conn, project: project, user: user} do
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

      assert %{
               "channel" => %{
                 "clientAuthMethodIds" => [wam_id],
                 "destinationCredentialId" => pc_id
               }
             } = form(view)

      assert wam_id == wam.id
      assert pc_id == pc.id
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

      # Remove wam1, add wam2, keep the destination credential
      save(view, %{
        "name" => channel.name,
        "destinationUrl" => channel.destination_url,
        "clientAuthMethodIds" => [wam2.id],
        "destinationCredentialId" => pc.id
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      assert [%{webhook_auth_method_id: client_id}] =
               auth_methods(channel, :client)

      assert client_id == wam2.id

      assert [%{project_credential_id: dest_id}] =
               auth_methods(channel, :destination)

      assert dest_id == pc.id
    end

    @tag role: :editor
    test "redirects when editing a channel that belongs to another project", %{
      conn: conn,
      project: project
    } do
      other_project = insert(:project)

      other_channel =
        insert(:channel,
          project: other_project,
          name: "other-tenant-channel",
          destination_url: "https://other.example.com"
        )

      assert {:error, {:live_redirect, %{to: redirect_to, flash: flash}}} =
               live(
                 conn,
                 ~p"/projects/#{project.id}/channels/#{other_channel.id}/edit"
               )

      assert redirect_to == ~p"/projects/#{project.id}/channels"
      assert flash["error"] == "Channel not found"
    end

    @tag role: :editor
    test "a client-side patch to another project's channel edit is rejected", %{
      conn: conn,
      project: project
    } do
      foreign_channel =
        insert(:channel, project: insert(:project), name: "other-tenant")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/channels")

      # Simulate a tampered browser pushing a live_patch straight to the
      # foreign channel's edit action. The channel index re-scopes on every
      # handle_params (apply_action/:edit loads via get_channel_for_project),
      # so the patch is rejected.
      assert {:error, {:live_redirect, %{to: to}}} =
               render_patch(
                 view,
                 ~p"/projects/#{project.id}/channels/#{foreign_channel.id}/edit"
               )

      assert to == ~p"/projects/#{project.id}/channels"
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

      save(view, %{
        "name" => "with-dest-cred",
        "destinationUrl" => "https://example.com/api",
        "destinationCredentialId" => pc.id
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")
      assert render(view) =~ "Channel created successfully"

      channel =
        Channels.list_channels_for_project(project.id)
        |> Enum.find(&(&1.name == "with-dest-cred"))

      assert channel

      assert [%{project_credential_id: dest_id}] =
               auth_methods(channel, :destination)

      assert dest_id == pc.id
    end

    @tag role: :editor
    test "creating a channel with None destination credential saves no auth method",
         %{conn: conn, project: project, user: user} do
      credential = insert(:credential, project: project, user: user)
      _pc = insert(:project_credential, project: project, credential: credential)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      save(view, %{
        "name" => "no-dest-cred",
        "destinationUrl" => "https://example.com/api",
        "destinationCredentialId" => ""
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      channel =
        Channels.list_channels_for_project(project.id)
        |> Enum.find(&(&1.name == "no-dest-cred"))

      assert channel
      assert auth_methods(channel, :destination) == []
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

      save(view, %{
        "name" => channel.name,
        "destinationUrl" => channel.destination_url,
        "destinationCredentialId" => pc2.id
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")

      assert [%{project_credential_id: dest_id}] =
               auth_methods(channel, :destination)

      assert dest_id == pc2.id
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

      save(view, %{
        "name" => channel.name,
        "destinationUrl" => channel.destination_url,
        "destinationCredentialId" => ""
      })

      assert_patch(view, ~p"/projects/#{project.id}/channels")
      assert auth_methods(channel, :destination) == []
    end
  end

  describe "cross-project destination credential is rejected" do
    @tag role: :editor
    test "creating a channel with another project's credential is rejected",
         %{conn: conn, project: project} do
      # The page only offers this project's credentials; a tampered browser
      # can still send an arbitrary project_credential UUID. It must be
      # rejected at save so a foreign tenant's secret can't be attached.
      other_project = insert(:project)
      victim_credential = insert(:project_credential, project: other_project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      save(view, %{
        "name" => "exfil",
        "destinationUrl" => "https://attacker.example.com",
        "destinationCredentialId" => victim_credential.id
      })

      # Refused, and the form stays open.
      assert_reply(view, %{error: _})
      assert form(view)
      assert Channels.list_channels_for_project(project.id) == []
    end

    @tag role: :editor
    test "swapping in another project's credential on edit is rejected",
         %{conn: conn, project: project, user: user} do
      credential = insert(:credential, project: project, user: user)

      own_pc =
        insert(:project_credential, project: project, credential: credential)

      other_project = insert(:project)
      victim_credential = insert(:project_credential, project: other_project)
      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        role: :destination,
        webhook_auth_method: nil,
        project_credential: own_pc
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      save(view, %{
        "name" => channel.name,
        "destinationUrl" => channel.destination_url,
        "destinationCredentialId" => victim_credential.id
      })

      assert_reply(view, %{error: _})
      assert form(view)

      # The existing destination credential is untouched; the foreign one
      # was never attached.
      assert [%{project_credential_id: dest_id}] =
               auth_methods(channel, :destination)

      assert dest_id == own_pc.id
    end
  end

  describe "cross-project client auth method is rejected" do
    @tag role: :editor
    test "creating a channel with another project's webhook auth method is rejected",
         %{conn: conn, project: project} do
      other_project = insert(:project)
      victim_auth_method = insert(:webhook_auth_method, project: other_project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/new")

      save(view, %{
        "name" => "borrowed-auth",
        "destinationUrl" => "https://example.com/destination",
        "clientAuthMethodIds" => [victim_auth_method.id]
      })

      assert Repo.preload(victim_auth_method, :channel_auth_methods).channel_auth_methods ==
               []

      for channel <- Channels.list_channels_for_project(project.id) do
        assert Repo.preload(channel, :client_auth_methods).client_auth_methods ==
                 []
      end
    end

    @tag role: :editor
    test "adding another project's webhook auth method on edit is rejected",
         %{conn: conn, project: project} do
      own_auth_method = insert(:webhook_auth_method, project: project)
      other_project = insert(:project)
      victim_auth_method = insert(:webhook_auth_method, project: other_project)
      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        role: :client,
        webhook_auth_method: own_auth_method
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/channels/#{channel.id}/edit")

      save(view, %{
        "name" => channel.name,
        "destinationUrl" => channel.destination_url,
        "clientAuthMethodIds" => [own_auth_method.id, victim_auth_method.id]
      })

      # The existing in-project client auth method is untouched; the foreign
      # one was never attached.
      assert [%{webhook_auth_method_id: client_id}] =
               auth_methods(channel, :client)

      assert client_id == own_auth_method.id

      assert Repo.preload(victim_auth_method, :channel_auth_methods).channel_auth_methods ==
               []
    end
  end
end
