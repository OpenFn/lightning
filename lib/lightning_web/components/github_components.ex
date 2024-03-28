defmodule LightningWeb.Components.GithubComponents do
  @moduledoc false

  use LightningWeb, :component

  attr :id, :string, required: true

  attr :class, :string,
    default:
      "text-center py-2 px-4 shadow-sm text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 bg-primary-600 hover:bg-primary-700 text-white"

  attr :user, Lightning.Accounts.User, required: true

  def connect_to_github_link(assigns) do
    ~H"""
    <.link
      id={@id}
      href={"https://github.com/login/oauth/authorize?" <> build_query_params()}
      target="_blank"
      class={@class}
      {if @user.github_oauth_token, do: ["phx-hook": "Tooltip", "aria-label": "Your token has expired"], else: []}
    >
      <%= if @user.github_oauth_token, do: "Reconnect", else: "Connect" %> your Github Account
    </.link>
    """
  end

  defp build_query_params do
    config = Application.fetch_env!(:lightning, :github_app)
    client_id = Keyword.fetch!(config, :client_id)

    redirect_url = url(LightningWeb.Endpoint, ~p"/oauth/github/callback")

    params = %{client_id: client_id, redirect_uri: redirect_url}

    Plug.Conn.Query.encode(params)
  end
end
