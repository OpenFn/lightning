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
          ~p"/projects/#{sandbox.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{sandbox_b.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
      assert result =~ "Add a credential"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
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
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
        )

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Trigger the webhook_auth_method_saved message
      # This simulates what happens when on_save callback is executed
      send(view.pid, :webhook_auth_method_saved)

      # Verify push_event was sent to React
      assert_push_event(view, "webhook_auth_method_saved", %{})

      # Verify PubSub broadcast was sent with webhook auth methods
      assert_receive %{
        event: "webhook_auth_methods_updated",
        payload: %{webhook_auth_methods: methods}
      }

      assert is_list(methods)
      # Should include our created auth method
      assert Enum.any?(methods, fn m ->
               m.id == auth_method.id && m.name == "Saved Auth Method"
             end)
    end

    test "broadcast_webhook_auth_methods_update includes all project methods", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      # Create multiple webhook auth methods
      auth1 =
        insert(:webhook_auth_method,
          project: project,
          name: "API Auth",
          auth_type: :api
        )

      auth2 =
        insert(:webhook_auth_method,
          project: project,
          name: "Basic Auth",
          auth_type: :basic,
          username: "testuser"
        )

      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
        )

      # Subscribe to verify broadcast
      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow.id}"
      )

      # Trigger broadcast by sending webhook_auth_method_saved
      send(view.pid, :webhook_auth_method_saved)

      # Verify broadcast contains all methods with correct structure
      assert_receive %{
        event: "webhook_auth_methods_updated",
        payload: %{webhook_auth_methods: methods}
      }

      assert length(methods) == 2

      # Verify first auth method structure
      api_method = Enum.find(methods, &(&1.id == auth1.id))
      assert api_method.name == "API Auth"
      assert api_method.auth_type == :api
      assert api_method.project_id == project.id
      assert api_method.inserted_at
      assert api_method.updated_at

      # Verify second auth method structure
      basic_method = Enum.find(methods, &(&1.id == auth2.id))
      assert basic_method.name == "Basic Auth"
      assert basic_method.auth_type == :basic
      assert basic_method.username == "testuser"
      assert basic_method.project_id == project.id
    end
  end
end
