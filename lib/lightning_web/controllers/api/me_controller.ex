defmodule LightningWeb.API.MeController do
  @moduledoc """
  `GET /api/me`: the person the token belongs to, in the shape
  `GET /api/users/:id` gives. A personal access token or a session token may
  read it; the service account and repo connections are not people and are
  refused 403 `forbidden`. A session token also gets what the account page
  shows; `identities`, `ai_disclaimer_accepted_at` and `consent` aren't stored
  yet, so they are always `[]`, `null` and `null`.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Scope
  alias LightningWeb.API.FallbackController
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction, {:users, :read_own_account}

  def show(conn, _params) do
    %Scope{actor: user} = scope = conn.assigns.scope

    account =
      if Scope.session?(scope) do
        %{
          mfa_enabled: user.mfa_enabled,
          has_password: not is_nil(user.hashed_password),
          inserted_at: user.inserted_at,
          confirmed_at: user.confirmed_at,
          contact_preference: user.contact_preference,
          experimental_features: Accounts.experimental_features_enabled?(user),
          has_activity_in_projects: Accounts.has_activity_in_projects?(user),
          pending_email: Accounts.pending_email(user),
          github: github(user.github_oauth_token),
          # Not stored yet: sent empty so a client finds every key.
          identities: [],
          ai_disclaimer_accepted_at: nil,
          consent: nil
        }
      end

    conn
    |> put_view(json: LightningWeb.API.UserJSON)
    |> render("me.json", user: user, account: account, conn: conn)
  end

  defp github(nil), do: %{connected: false, expires_at: nil}

  defp github(token) do
    %{
      connected: Lightning.VersionControl.oauth_token_valid?(token),
      expires_at: token["refresh_token_expires_at"]
    }
  end
end
