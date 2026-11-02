defmodule LightningWeb.API.MeControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Accounts

  defp bearer(token) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
  end

  defp user_resource(user) do
    %{
      "type" => "users",
      "id" => user.id,
      "attributes" => %{
        "email" => user.email,
        "first_name" => user.first_name,
        "last_name" => user.last_name,
        "role" => "user"
      },
      "links" => %{
        "self" => LightningWeb.Endpoint.url() <> "/api/users/#{user.id}"
      }
    }
  end

  test "reading yourself with a personal access token gives the user, as GET /api/users/:id shapes it" do
    user = insert(:user)

    conn = user |> Accounts.generate_api_token() |> bearer() |> get(~p"/api/me")

    assert json_response(conn, 200) == %{"data" => user_resource(user)}
  end

  test "reading yourself with a session token adds what the account page shows" do
    user =
      insert(:user,
        mfa_enabled: true,
        contact_preference: :any,
        preferences: %{"experimental_features" => true},
        github_oauth_token: %{
          "access_token" => "gho_x",
          "refresh_token_expires_at" => "2027-01-01T00:00:00Z"
        }
      )

    {:ok, _email} = Accounts.request_email_update(user, "new@example.com")

    conn = build_conn() |> session_conn(user) |> get(~p"/api/me")
    expected = user_resource(user)

    assert json_response(conn, 200) == %{
             "data" =>
               Map.update!(
                 expected,
                 "attributes",
                 &Map.merge(&1, %{
                   "mfa_enabled" => true,
                   "has_password" => true,
                   "inserted_at" => DateTime.to_iso8601(user.inserted_at),
                   "confirmed_at" => nil,
                   "contact_preference" => "any",
                   "experimental_features" => true,
                   "has_activity_in_projects" => false,
                   "pending_email" => "new@example.com",
                   "github" => %{
                     "connected" => true,
                     "expires_at" => "2027-01-01T00:00:00Z"
                   },
                   "identities" => [],
                   "ai_disclaimer_accepted_at" => nil,
                   "consent" => nil
                 })
               )
           }
  end
end
