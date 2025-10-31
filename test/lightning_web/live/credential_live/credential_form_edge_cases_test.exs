defmodule LightningWeb.CredentialLive.CredentialFormEdgeCasesTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Phoenix.LiveViewTest

  alias LightningWeb.TestCredentialEditorLive

  describe "credential form edit with return_to: nil" do
    test "blocks editing another user's credential when return_to is nil", %{
      conn: conn
    } do
      user = insert(:user)
      other_user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      # Create credential owned by another user
      credential =
        insert(:credential,
          name: "Other User Credential",
          schema: "raw",
          user: other_user,
          body: %{"test" => "value"}
        )

      insert(:project_credential, project: project, credential: credential)

      # Preload associations that the form component needs
      credential =
        Lightning.Credentials.get_credential!(credential.id)
        |> Lightning.Repo.preload(:project_credentials)

      conn = log_in_user(conn, user)

      # Mount test LiveView with return_to: nil
      {:ok, view, _html} =
        live_isolated(conn, TestCredentialEditorLive,
          session: %{
            "current_user" => user,
            "project" => project,
            "credential" => credential,
            "return_to" => nil
          }
        )

      # Try to update the credential - should be blocked because user doesn't own it
      view
      |> element("form#credential-form-#{credential.id}")
      |> render_submit(%{
        "credential" => %{
          "name" => "Hijacked Name",
          "body" => Jason.encode!(%{"hacked" => "value"})
        }
      })

      # Verify credential was NOT updated
      # This covers the else branch in save_credential for :edit with return_to: nil (lines 781-795)
      updated_credential =
        Lightning.Credentials.get_credential!(credential.id)

      assert updated_credential.name == "Other User Credential"

      # View should still render (not crash/redirect)
      assert render(view)
    end
  end
end
