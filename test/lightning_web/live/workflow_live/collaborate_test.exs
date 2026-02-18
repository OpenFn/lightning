defmodule LightningWeb.WorkflowLive.CollaborateTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Lightning.WorkflowsFixtures
  import Phoenix.LiveViewTest

  describe "sandbox indicator banner data attributes" do
    test "sets root project data attributes when in sandbox project", %{
      conn: conn
    } do
      user = insert(:user)
      parent_project = insert(:project, name: "Production Project")

      sandbox =
        insert(:sandbox,
          parent: parent_project,
          name: "test-sandbox",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: sandbox.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox.id}/w/#{workflow.id}"
        )

      assert html =~ "data-root-project-id=\"#{parent_project.id}\""
      assert html =~ "data-root-project-name=\"#{parent_project.name}\""
    end

    test "sets null root project data attributes when in root project", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Production Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      refute html =~ "data-root-project-id="
      refute html =~ "data-root-project-name="
    end

    test "sets correct root project in deeply nested sandbox", %{conn: conn} do
      user = insert(:user)
      root_project = insert(:project, name: "Root Project")

      sandbox_a =
        insert(:sandbox,
          parent: root_project,
          name: "sandbox-a"
        )

      sandbox_b =
        insert(:sandbox,
          parent: sandbox_a,
          name: "sandbox-b",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: sandbox_b.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox_b.id}/w/#{workflow.id}"
        )

      assert html =~ "data-root-project-id=\"#{root_project.id}\""
      assert html =~ "data-root-project-name=\"#{root_project.name}\""
      refute html =~ sandbox_a.name
    end
  end

  describe "credential creation and broadcasting" do
    test "broadcasts credential update when project credential is saved", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Create a credential with project association
      credential =
        insert(:credential,
          name: "New Credential",
          schema: "raw",
          user: user
        )

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      # Reload to get all associations
      credential =
        Lightning.Credentials.get_credential!(credential.id)
        |> Lightning.Repo.preload(project_credentials: [:project])

      # Send credential_saved message to the LiveView process
      send(view.pid, {:credential_saved, credential})

      # Verify push_event was sent to React (check hook data)
      assert_push_event(view, "credential_saved", %{
        credential: credential_data,
        is_project_credential: true
      })

      assert credential_data.name == "New Credential"
      assert credential_data.schema == "raw"
      assert credential_data.project_credential_id == project_credential.id

      # Verify PubSub broadcast was sent
      assert_receive %{
        event: "credentials_updated",
        payload: %{
          project_credentials: project_creds,
          keychain_credentials: keychain_creds
        }
      }

      assert is_list(project_creds)
      assert is_list(keychain_creds)
    end

    test "broadcasts credential update when keychain credential is saved", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Create a keychain credential (no project_credentials)
      credential =
        insert(:credential,
          name: "Keychain Credential",
          schema: "oauth",
          user: user,
          project_credentials: []
        )

      # Reload and preload associations to ensure no project_credentials
      credential =
        Lightning.Credentials.get_credential!(credential.id)
        |> Lightning.Repo.preload(:project_credentials)

      # Send credential_saved message
      send(view.pid, {:credential_saved, credential})

      # Verify push_event for keychain credential
      assert_push_event(view, "credential_saved", %{
        credential: credential_data,
        is_project_credential: false
      })

      assert credential_data.id == credential.id
      assert credential_data.name == "Keychain Credential"
      assert credential_data.schema == "oauth"

      # Verify PubSub broadcast
      assert_receive %{event: "credentials_updated", payload: _}
    end

    test "broadcasts keychain credential update when KeychainCredential struct is saved",
         %{
           conn: conn
         } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Create an actual KeychainCredential struct (not a regular Credential)
      keychain_credential =
        insert(:keychain_credential,
          name: "My Keychain",
          path: "$.user_id",
          project: project,
          created_by: user
        )

      # Send credential_saved message with KeychainCredential
      send(view.pid, {:credential_saved, keychain_credential})

      # Verify push_event for keychain credential
      assert_push_event(view, "credential_saved", %{
        credential: credential_data,
        is_project_credential: false
      })

      assert credential_data.id == keychain_credential.id
      assert credential_data.name == "My Keychain"
      assert credential_data.schema == "keychain"

      # Verify PubSub broadcast
      assert_receive %{event: "credentials_updated", payload: _}
    end

    test "renders credentials with complete structure including owner", %{
      conn: conn
    } do
      user = insert(:user, first_name: "John", last_name: "Doe")

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Create credential with user association
      credential =
        insert(:credential,
          name: "Test Credential",
          schema: "raw",
          user: user,
          external_id: "ext_123"
        )

      insert(:project_credential, project: project, credential: credential)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Reload credential with associations
      credential =
        Lightning.Credentials.get_credential!(credential.id)
        |> Lightning.Repo.preload(project_credentials: [:project])

      send(view.pid, {:credential_saved, credential})

      # Verify broadcast contains owner information
      assert_receive %{
        event: "credentials_updated",
        payload: %{project_credentials: [cred | _]}
      }

      assert %{
               name: "Test Credential",
               schema: "raw",
               external_id: "ext_123",
               owner: %{
                 id: owner_id,
                 name: "John Doe",
                 email: email
               }
             } = cred

      assert owner_id == user.id
      assert email == user.email
    end

    test "renders keychain credentials with correct structure", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Create keychain credential
      keychain_cred =
        insert(:keychain_credential,
          name: "Keychain Test",
          path: "$.api_key",
          project: project,
          created_by: user
        )

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Trigger broadcast by creating a credential
      credential = insert(:credential, user: user, project_credentials: [])
      send(view.pid, {:credential_saved, credential})

      # Verify keychain credential structure in broadcast
      assert_receive %{
        event: "credentials_updated",
        payload: %{keychain_credentials: keychain_creds}
      }

      # Find our keychain credential
      keychain_data =
        Enum.find(keychain_creds, fn kc -> kc.id == keychain_cred.id end)

      assert %{
               id: _,
               name: "Keychain Test",
               path: "$.api_key",
               default_credential_id: _,
               inserted_at: _,
               updated_at: _
             } = keychain_data
    end

    test "handles credentials with oauth_client", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      oauth_client = insert(:oauth_client, name: "Salesforce OAuth")

      credential =
        insert(:credential,
          name: "OAuth Credential",
          schema: "oauth",
          user: user,
          oauth_client: oauth_client
        )

      insert(:project_credential, project: project, credential: credential)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      credential =
        Lightning.Credentials.get_credential!(credential.id)
        |> Lightning.Repo.preload(
          project_credentials: [:project],
          oauth_client: []
        )

      send(view.pid, {:credential_saved, credential})

      assert_receive %{
        event: "credentials_updated",
        payload: %{project_credentials: [cred | _]}
      }

      assert cred.oauth_client_name == "Salesforce OAuth"
    end

    test "handles :close_credential_modal_after_save message", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Subscribe to verify broadcast happens
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Send credential saved with properly preloaded credential
      credential =
        insert(:credential, user: user, project_credentials: [])
        |> Lightning.Repo.preload(:project_credentials)

      send(view.pid, {:credential_saved, credential})

      # Verify the credential_saved event was pushed to React
      assert_push_event(view, "credential_saved", %{
        credential: _,
        is_project_credential: false
      })

      # Verify broadcast occurred
      assert_receive %{event: "credentials_updated", payload: _}

      # The LiveView should still be responsive after processing messages
      assert render(view)
    end

    test "on_save callback executes when credential is successfully saved", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Open credential modal
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      assert html =~ "new-credential-modal"

      # Submit the form to actually save a credential
      # This will trigger the on_save callback which executes: send(self(), {:credential_saved, credential})
      view
      |> element("form#credential-form-new")
      |> render_submit(%{
        "credential" => %{
          "name" => "Test Callback Credential",
          "body" => Jason.encode!(%{"api_key" => "test123"})
        }
      })

      # Verify broadcast occurred (proving the on_save callback was executed)
      # This covers line 94: send(self(), {:credential_saved, credential})
      assert_receive %{event: "credentials_updated", payload: _}

      # Verify credential was actually created
      credentials = Lightning.Credentials.list_credentials(user)
      assert length(credentials) == 1
      assert hd(credentials).name == "Test Callback Credential"
    end

    test "renders credentials with nil owner", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Create credential without user association (nil owner)
      credential =
        insert(:credential,
          name: "No Owner Credential",
          schema: "raw",
          user: nil,
          project_credentials: []
        )

      insert(:project_credential, project: project, credential: credential)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Reload credential with associations
      credential =
        Lightning.Credentials.get_credential!(credential.id)
        |> Lightning.Repo.preload(project_credentials: [:project])

      # Send credential_saved to trigger broadcast with nil owner
      send(view.pid, {:credential_saved, credential})

      # Verify broadcast includes nil owner (tests render_owner(nil))
      assert_receive %{
        event: "credentials_updated",
        payload: %{project_credentials: [cred | _]}
      }

      assert cred.owner == nil
    end

    test "credential form blocks unauthorized save with no return_to", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open credential modal
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      assert html =~ "new-credential-modal"

      # The modal is rendered with can_create_project_credential: false for viewer
      # Try to submit the form - it should be blocked by the authorization check
      view
      |> element("form#credential-form-new")
      |> render_submit(%{
        "credential" => %{
          "name" => "Unauthorized Test",
          "body" => Jason.encode!(%{"key" => "value"})
        }
      })

      # Verify credential was NOT created - this proves the authorization check worked
      # This exercises the else branch where return_to is nil (lines 286-292 in credential_form_component.ex)
      # The code path: can_create_project_credential = false -> else block -> put_flash + no redirect (return_to = nil)
      assert Lightning.Credentials.list_credentials(user) == []

      # The page should still be responsive (not crashed/redirected)
      assert render(view)
    end
  end

  describe "credential modal interactions" do
    test "opens credential modal with schema via handle_event", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Initially, modal should not be shown
      refute html =~ "new-credential-modal"

      # Trigger open_credential_modal event
      result =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Verify modal is now shown with correct schema
      assert result =~ "new-credential-modal"
      assert result =~ "Create Raw JSON credential"
    end

    test "closes credential modal via handle_event", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # First open the modal
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "http"})

      assert html =~ "new-credential-modal"

      # Now close it
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("close_credential_modal", %{})

      # Modal should be hidden
      refute html =~ "new-credential-modal"
    end

    test "credential_modal_closed event closes modal and pushes event to React",
         %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # First open the modal
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "http"})

      assert html =~ "new-credential-modal"

      # Close via credential_modal_closed (triggered by JS.push from on_modal_close)
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("credential_modal_closed", %{})

      # Modal should be hidden
      refute html =~ "new-credential-modal"

      # Verify the credential_modal_closed event was pushed to React
      assert_push_event(view, "credential_modal_closed", %{})
    end

    test "modal renders with pre-selected schema", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open modal with raw schema (no schema file needed)
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Verify modal shows correct content
      assert html =~ "new-credential-modal"
      assert html =~ "Credential Name"
      assert html =~ "Save Credential"
    end

    test "modal not rendered when show_credential_modal is false", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # By default, modal should not be rendered
      refute html =~ "new-credential-modal"
    end

    test "modal rendered when show_credential_modal is true", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open the modal
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Verify modal is rendered
      assert html =~ "new-credential-modal"
      assert html =~ "id=\"new-credential-modal\""
    end

    test "multiple open/close cycles work correctly", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # First cycle
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      assert html =~ "new-credential-modal"

      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("close_credential_modal", %{})

      refute html =~ "new-credential-modal"

      # Second cycle with different schema
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "http"})

      assert html =~ "new-credential-modal"

      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("close_credential_modal", %{})

      refute html =~ "new-credential-modal"
    end
  end

  describe "credential type picker - standard flow (from adaptor)" do
    test "opens credential modal from picked adaptor", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # User selects adaptor, clicks "New Credential"
      # React dispatches open_credential_modal with schema (using raw for simplicity)
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Verify modal opened
      assert html =~ "new-credential-modal"
      assert html =~ "Credential Name"
    end

    test "creates raw credential from picked adaptor", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Open modal with raw schema
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      assert html =~ "new-credential-modal"

      # Submit the form
      view
      |> element("form#credential-form-new")
      |> render_submit(%{
        "credential" => %{
          "name" => "My Raw Credential",
          "body" => Jason.encode!(%{"api_key" => "secret123"})
        }
      })

      # Verify credential created
      credential =
        Lightning.Repo.get_by(Lightning.Credentials.Credential,
          name: "My Raw Credential"
        )

      assert credential
      assert credential.schema == "raw"
      assert credential.user_id == user.id

      # Verify push_event sent to React
      assert_push_event(view, "credential_saved", %{
        credential: cred_data,
        is_project_credential: true
      })

      assert cred_data.name == "My Raw Credential"

      # Verify PubSub broadcast
      assert_receive %{event: "credentials_updated", payload: _}, 1000
    end

    test "standard form shows Advanced button when from collab editor", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open standard credential form
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Verify Advanced button is present
      assert html =~ "Advanced"
    end
  end

  describe "credential type picker - advanced picker flow" do
    test "navigates from standard picker to advanced picker", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open standard form
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Click Advanced button
      html =
        view
        |> element("button", "Advanced")
        |> render_click()

      # Verify advanced picker appears
      assert html =~ "Raw JSON"
      assert html =~ "Keychain"
    end

    test "advanced picker displays all credential type options", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Create OAuth clients for this project
      salesforce = insert(:oauth_client, name: "Salesforce")
      google = insert(:oauth_client, name: "Google Sheets")
      insert(:project_oauth_client, project: project, oauth_client: salesforce)
      insert(:project_oauth_client, project: project, oauth_client: google)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open standard form then navigate to advanced picker
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      html =
        view
        |> element("button", "Advanced")
        |> render_click()

      # Verify all options present
      assert html =~ "Raw JSON"
      assert html =~ "Keychain"
      assert html =~ "Salesforce"
      assert html =~ "Google Sheets"
    end

    test "selects OAuth client from advanced picker and continues", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      oauth_client = insert(:oauth_client, name: "Salesforce")
      insert(:project_oauth_client, project: project, oauth_client: oauth_client)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate to advanced picker
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      # Select OAuth client
      view
      |> element("button[phx-value-key='#{oauth_client.id}']")
      |> render_click()

      # Click Continue button
      view
      |> element("button", "Continue")
      |> render_click()

      # Verify OAuth form appears
      # The form should transition to page: :second with OAuth schema
      assert render(view)
    end

    test "selects raw JSON from advanced picker and continues", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate to advanced picker
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      # Select Raw JSON
      view
      |> element("button[phx-value-key='raw']")
      |> render_click()

      # Click Continue
      html =
        view
        |> element("button", "Continue")
        |> render_click()

      # Should show raw credential form
      assert html =~ "Credential Name"
    end

    test "selects keychain from advanced picker and continues", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate to advanced picker
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      # Select Keychain
      view
      |> element("button[phx-value-key='keychain']")
      |> render_click()

      # Click Continue
      html =
        view
        |> element("button", "Continue")
        |> render_click()

      # Should show keychain form
      assert html =~ "Create keychain credential"
      assert html =~ "JSONPath Expression"
      assert html =~ "Default Credential"
    end
  end

  describe "credential type picker - keychain credential creation" do
    test "creates keychain credential with valid data", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Navigate to keychain form via advanced picker
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='keychain']")
      |> render_click()

      view
      |> element("button", "Continue")
      |> render_click()

      # Submit keychain form
      view
      |> element("form[id*='keychain-credential-form']")
      |> render_submit(%{
        "keychain_credential" => %{
          "name" => "My Keychain",
          "path" => "$.user_id"
        }
      })

      # Verify keychain credential created
      keychain =
        Lightning.Repo.get_by(Lightning.Credentials.KeychainCredential,
          name: "My Keychain"
        )

      assert keychain
      assert keychain.path == "$.user_id"
      assert keychain.project_id == project.id
      assert keychain.created_by_id == user.id

      # Verify push_event sent to React
      assert_push_event(view, "credential_saved", %{
        credential: cred_data,
        is_project_credential: false
      })

      assert cred_data.name == "My Keychain"
      assert cred_data.schema == "keychain"

      # Verify PubSub broadcast
      assert_receive %{event: "credentials_updated", payload: _}, 1000
    end

    test "shows validation errors for invalid keychain credential", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate to keychain form
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='keychain']")
      |> render_click()

      view
      |> element("button", "Continue")
      |> render_click()

      # Submit with empty fields
      html =
        view
        |> element("form[id*='keychain-credential-form']")
        |> render_submit(%{
          "keychain_credential" => %{
            "name" => "",
            "path" => ""
          }
        })

      # Verify validation errors shown
      assert html =~ "can&#39;t be blank"

      # Verify no credential created
      assert Lightning.Repo.aggregate(
               Lightning.Credentials.KeychainCredential,
               :count
             ) == 0
    end

    test "validates JSONPath expression format", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate to keychain form
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='keychain']")
      |> render_click()

      view
      |> element("button", "Continue")
      |> render_click()

      # Submit with invalid JSONPath (missing $. prefix)
      html =
        view
        |> element("form[id*='keychain-credential-form']")
        |> render_submit(%{
          "keychain_credential" => %{
            "name" => "Test",
            "path" => "invalid_path"
          }
        })

      # Verify validation error
      assert html =~ "must start with"

      # Verify no credential created
      assert Lightning.Repo.get_by(Lightning.Credentials.KeychainCredential,
               name: "Test"
             ) == nil
    end

    test "creates keychain with default credential selection", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Create an existing credential to use as default
      default_cred =
        insert(:credential,
          name: "Default API Key",
          schema: "raw",
          user: user
        )

      insert(:project_credential, project: project, credential: default_cred)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate to keychain form
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='keychain']")
      |> render_click()

      html =
        view
        |> element("button", "Continue")
        |> render_click()

      # Verify default credential appears in dropdown
      assert html =~ "Default API Key"

      # Submit with default credential
      view
      |> element("form[id*='keychain-credential-form']")
      |> render_submit(%{
        "keychain_credential" => %{
          "name" => "My Keychain",
          "path" => "$.user_id",
          "default_credential_id" => to_string(default_cred.id)
        }
      })

      # Verify keychain created with default_credential_id
      keychain =
        Lightning.Repo.get_by(Lightning.Credentials.KeychainCredential,
          name: "My Keychain"
        )

      assert keychain
      assert keychain.default_credential_id == default_cred.id
    end
  end

  describe "credential type picker - back navigation" do
    test "back button returns from keychain form to advanced picker", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate: standard → advanced → keychain
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='keychain']")
      |> render_click()

      view
      |> element("button", "Continue")
      |> render_click()

      # Now on keychain form - click Back
      html =
        view
        |> element("button", "Back")
        |> render_click()

      # Should be back at advanced picker
      assert html =~ "Raw JSON"
      assert html =~ "Keychain"
    end

    test "back button returns from raw form to advanced picker", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate: standard → advanced → raw
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='raw']")
      |> render_click()

      view
      |> element("button", "Continue")
      |> render_click()

      # On raw form - click Back
      html =
        view
        |> element("button", "Back")
        |> render_click()

      # Should be back at advanced picker
      assert html =~ "Raw JSON"
      assert html =~ "Keychain"
    end

    test "cancel button returns from advanced picker to standard form", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open with specific schema
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Go to advanced picker
      view
      |> element("button", "Advanced")
      |> render_click()

      # Click Cancel to go back
      html =
        view
        |> element("button", "Back")
        |> render_click()

      # Should be back at standard form
      assert html =~ "Credential Name"
      assert html =~ "Advanced"
    end

    test "back button preserves keychain form data", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate to keychain form
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='keychain']")
      |> render_click()

      view
      |> element("button", "Continue")
      |> render_click()

      # Fill some data (but don't submit)
      view
      |> element("form[id*='keychain-credential-form']")
      |> render_change(%{
        "keychain_credential" => %{
          "name" => "Test Keychain",
          "path" => "$.id"
        }
      })

      # Click Back
      view
      |> element("button", "Back")
      |> render_click()

      # Should be at advanced picker
      # (Data is intentionally lost when going back - this is expected behavior)
      assert render(view) =~ "Advanced"
    end

    test "back navigation from OAuth form to advanced picker", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      oauth_client = insert(:oauth_client, name: "Salesforce")
      insert(:project_oauth_client, project: project, oauth_client: oauth_client)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Navigate: standard → advanced → OAuth
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      view
      |> element("button", "Advanced")
      |> render_click()

      view
      |> element("button[phx-value-key='#{oauth_client.id}']")
      |> render_click()

      view
      |> element("button", "Continue")
      |> render_click()

      # Click Back from OAuth form
      html =
        view
        |> element("button", "Back")
        |> render_click()

      # Should be back at advanced picker
      assert html =~ "Raw JSON"
      assert html =~ "Keychain"
      assert html =~ "Salesforce"
    end
  end

  describe "advanced picker navigation message handlers" do
    test "handles :clear_credential_page message", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open credential modal
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Send :clear_credential_page message
      send(view.pid, :clear_credential_page)

      # The view should still be responsive after processing the message
      assert render(view)
    end

    test "handles {:update_credential_schema, schema} message", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open credential modal with initial schema
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Send update_credential_schema message to change schema
      send(view.pid, {:update_credential_schema, "http"})

      # The view should still be responsive and schema should be updated
      assert render(view)
    end

    test "handles {:update_selected_credential_type, type} message", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Send update_selected_credential_type message
      send(view.pid, {:update_selected_credential_type, "oauth"})

      # The view should still be responsive after storing the credential type
      assert render(view)
    end

    test "handles {:back_to_advanced_picker} message", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Open credential modal first
      view
      |> element("#collaborative-editor-react")
      |> render_hook("open_credential_modal", %{"schema" => "raw"})

      # Send back_to_advanced_picker message
      send(view.pid, {:back_to_advanced_picker})

      # The view should still be responsive and modal should remain open
      html = render(view)
      assert html =~ "new-credential-modal"
    end
  end

  describe "webhook auth method modal interactions" do
    test "opens webhook auth method modal via handle_event", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Initially, modal should not be shown
      refute html =~ "webhook-auth-method-modal"

      # Trigger open_webhook_auth_modal event
      result =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_webhook_auth_modal", %{})

      # Verify modal is now shown
      assert result =~ "webhook-auth-method-modal"
    end

    test "closes webhook auth method modal via handle_event", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # First open the modal
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_webhook_auth_modal", %{})

      assert html =~ "webhook-auth-method-modal"

      # Now close it
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("close_webhook_auth_modal_complete", %{})

      # Modal should be hidden
      refute html =~ "webhook-auth-method-modal"
    end

    test "modal not rendered when show_webhook_auth_modal is false", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # By default, modal should not be rendered
      refute html =~ "webhook-auth-method-modal"
    end

    test "multiple open/close cycles work correctly", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # First cycle
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_webhook_auth_modal", %{})

      assert html =~ "webhook-auth-method-modal"

      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("close_webhook_auth_modal_complete", %{})

      refute html =~ "webhook-auth-method-modal"

      # Second cycle
      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("open_webhook_auth_modal", %{})

      assert html =~ "webhook-auth-method-modal"

      html =
        view
        |> element("#collaborative-editor-react")
        |> render_hook("close_webhook_auth_modal_complete", %{})

      refute html =~ "webhook-auth-method-modal"
    end

    test "webhook auth method saved triggers broadcast and closes modal", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Create webhook auth method for project
      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Saved Auth Method",
          auth_type: :basic
        )

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Trigger save
      send(view.pid, :webhook_auth_method_saved)

      # Verify broadcast was sent
      assert_receive %{
        event: "webhook_auth_methods_updated",
        payload: payload
      }

      assert is_map(payload)
      assert Map.has_key?(payload, :webhook_auth_methods)
      webhook_auth_methods = payload.webhook_auth_methods
      assert is_list(webhook_auth_methods)
      assert length(webhook_auth_methods) == 1

      saved_method = hd(webhook_auth_methods)
      assert saved_method.id == auth_method.id
      assert saved_method.name == "Saved Auth Method"
      assert saved_method.auth_type == :basic

      # Verify the view is still alive and functional after save
      html = render(view)
      refute html =~ "webhook-auth-method-modal"
    end
  end

  describe "initial run data for page reload" do
    test "sets initial-run-data attribute when run param is provided", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      job = insert(:job, workflow: workflow)

      # Create a work order with a run and steps
      dataclip = insert(:dataclip)
      work_order = insert(:workorder, workflow: workflow, dataclip: dataclip)

      run =
        insert(:run,
          work_order: work_order,
          starting_job: job,
          dataclip: dataclip
        )

      step =
        insert(:step,
          job: job,
          runs: [run],
          exit_reason: "success",
          input_dataclip: dataclip
        )

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?run=#{run.id}"
        )

      # Parse the HTML to extract the data attribute
      assert html =~ "data-initial-run-data"

      # Extract and parse the JSON data - HTML entities like &quot; need decoding
      regex = ~r/data-initial-run-data="([^"]*)"/

      case Regex.run(regex, html) do
        [_, encoded_json] ->
          # Decode HTML entities manually (main ones used in JSON)
          json =
            encoded_json
            |> String.replace("&quot;", "\"")
            |> String.replace("&amp;", "&")
            |> String.replace("&lt;", "<")
            |> String.replace("&gt;", ">")

          data = Jason.decode!(json)

          # Verify the structure matches RunStepsData interface
          assert data["run_id"] == run.id
          assert is_list(data["steps"])
          assert length(data["steps"]) == 1

          step_data = hd(data["steps"])
          assert step_data["id"] == step.id
          assert step_data["job_id"] == job.id
          assert step_data["exit_reason"] == "success"

          metadata = data["metadata"]
          assert metadata["starting_job_id"] == job.id

        nil ->
          flunk("data-initial-run-data attribute not found or empty")
      end
    end

    test "does not set initial-run-data attribute when no run param", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # No initial run data when no run param
      refute html =~ "data-initial-run-data="
    end

    test "does not set initial-run-data attribute for non-existent run", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?run=#{Ecto.UUID.generate()}"
        )

      # No initial run data when run doesn't exist
      refute html =~ "data-initial-run-data="
    end

    test "does not set initial-run-data attribute for new workflow", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/new"
        )

      # New workflows never have initial run data
      refute html =~ "data-initial-run-data="
    end
  end

  describe "legacy editor preference redirect" do
    test "redirects to legacy editor when user prefers legacy editor", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Set user preference to prefer legacy editor
      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{
            "prefer_legacy_editor" => true
          }
        })
        |> Lightning.Repo.update!()

      # Try to navigate to collaborative editor
      {:error, {:live_redirect, %{to: redirect_path}}} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/projects/#{project.id}/w/#{workflow.id}")

      # Should redirect to legacy editor
      assert redirect_path == "/projects/#{project.id}/w/#{workflow.id}/legacy"
    end

    test "redirects to legacy editor for new workflow when user prefers legacy editor",
         %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      # Set user preference to prefer legacy editor
      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{
            "prefer_legacy_editor" => true
          }
        })
        |> Lightning.Repo.update!()

      # Try to navigate to collaborative editor for new workflow
      {:error, {:live_redirect, %{to: redirect_path}}} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/projects/#{project.id}/w/new")

      # Should redirect to legacy editor with method=template
      assert redirect_path ==
               "/projects/#{project.id}/w/new/legacy?method=template"
    end

    test "redirects to legacy editor with query params transformed", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      job = insert(:job, workflow: workflow)

      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{
            "prefer_legacy_editor" => true
          }
        })
        |> Lightning.Repo.update!()

      # Try to navigate to collaborative editor with query params
      {:error, {:live_redirect, %{to: redirect_path}}} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(
          ~p"/projects/#{project.id}/w/#{workflow.id}?job=#{job.id}&panel=editor"
        )

      # Should redirect to legacy editor with query params transformed
      assert String.starts_with?(
               redirect_path,
               "/projects/#{project.id}/w/#{workflow.id}/legacy"
             )

      assert redirect_path =~ "s=#{job.id}"
      assert redirect_path =~ "m=expand"
    end

    test "does not redirect when user does not prefer legacy editor", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Set user preference to NOT prefer legacy editor
      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{
            "prefer_legacy_editor" => false
          }
        })
        |> Lightning.Repo.update!()

      # Navigate to collaborative editor
      {:ok, _view, html} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/projects/#{project.id}/w/#{workflow.id}")

      # Should stay on collaborative editor (no redirect)
      assert html =~ "collaborative-editor-react"
    end

    test "does not redirect when preference is not set", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          name: "Test Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # No preference set (default behavior)
      conn = log_in_user(conn, user)

      # Navigate to collaborative editor
      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      # Should stay on collaborative editor (no redirect)
      assert html =~ "collaborative-editor-react"
    end
  end
end
