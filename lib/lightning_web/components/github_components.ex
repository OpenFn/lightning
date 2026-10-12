defmodule LightningWeb.Components.GithubComponents do
  @moduledoc false

  use LightningWeb, :component

  attr :id, :string, required: true
  attr :user, Lightning.Accounts.User, required: true
  attr :github_query_params, :map
  attr :disabled, :boolean, default: false

  def connect_to_github_link(assigns) do
    assigns =
      assign_new(assigns, :github_query_params, fn -> build_query_params() end)

    ~H"""
    <.button_link
      id={@id}
      theme="primary"
      href={"https://github.com/login/oauth/authorize?" <> Plug.Conn.Query.encode(@github_query_params)}
      target="_blank"
      disabled={@disabled}
      phx-hook={@user.github_oauth_token && "Tooltip"}
      aria-label={@user.github_oauth_token && "Your token has expired"}
    >
      {if @user.github_oauth_token, do: "Reconnect", else: "Connect"} your GitHub Account
    </.button_link>
    """
  end

  attr :class, :string, default: "mb-4", doc: "spacing classes for the banner"

  @doc """
  Blue info banner pointing to the GitHub sync docs. Shown inside each state of
  the Sync tab's GitHub panel.
  """
  def sync_docs_banner(assigns) do
    ~H"""
    <Common.alert id="github-sync-docs-banner" type="info" class={@class}>
      <:message>
        Learn more about synchronizing your project with GitHub at
        <.link
          target="_blank"
          href="https://docs.openfn.org/documentation/link-to-GitHub"
          class="font-medium underline"
        >
          docs.openfn.org
        </.link>
      </:message>
    </Common.alert>
    """
  end

  defp build_query_params do
    config = Application.fetch_env!(:lightning, :github_app)
    client_id = Keyword.fetch!(config, :client_id)

    redirect_url = url(LightningWeb.Endpoint, ~p"/oauth/github/callback")

    %{client_id: client_id, redirect_uri: redirect_url}
  end
end
