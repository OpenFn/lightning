defmodule LightningWeb.API.InstanceController do
  @moduledoc """
  `GET /api/instance`: what Lightning's own app needs to know about the
  instance before anyone signs in. It takes no token. The support address,
  `admin_email`, is `null` unless the request carries a signed-in session
  token from Lightning's own pages.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.Components.GithubComponents
  alias LightningWeb.SessionToken

  def show(conn, _params) do
    {session, conn} = SessionToken.read(conn)
    github_sync? = Lightning.VersionControl.github_enabled?() |> truthy?()

    render(conn, :show,
      instance: %{
        # First setup is off whenever a service account is configured.
        needs_setup:
          Lightning.Config.check_flag?(:allow_first_setup) == true and
            not Accounts.has_one_superuser?(),
        allow_signup: Lightning.Config.check_flag?(:allow_signup) == true,
        url: LightningWeb.Endpoint.url(),
        release: Lightning.release(),
        admin_email:
          if(match?(%{state: :signed_in}, session),
            do: Lightning.Config.instance_admin_email()
          ),
        purge_deleted_after_days: Lightning.Config.purge_deleted_after_days(),
        sign_in_providers: sign_in_providers(),
        ai_assistant: Lightning.AiAssistant.enabled?() |> truthy?(),
        github_sync: github_sync?,
        github_connect_url: if(github_sync?, do: GithubComponents.connect_url())
      }
    )
  end

  # Only OpenID Connect providers sign people in. GitHub's app only connects
  # an account for GitHub sync.
  defp sign_in_providers do
    {:ok, handlers} = Lightning.AuthProviders.get_handlers()

    for handler <- handlers do
      %{
        name: handler.name,
        kind: "external",
        start_url: url(~p"/authenticate/#{handler.name}")
      }
    end
  end

  defp truthy?(value), do: value not in [nil, false]
end
