defmodule LightningWeb.Components.GithubComponents do
  @moduledoc false

  use LightningWeb, :component

  attr :id, :string, required: true

  attr :class, :string,
    default:
      "text-center py-2 px-4 shadow-xs text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 bg-primary-600 hover:bg-primary-700 text-white"

  attr :user, Lightning.Accounts.User, required: true
  attr :github_query_params, :map
  attr :disabled, :boolean, default: false

  def connect_to_github_link(assigns) do
    assigns =
      assign_new(assigns, :github_query_params, fn -> build_query_params() end)

    ~H"""
    <.link
      id={@id}
      href={"https://github.com/login/oauth/authorize?" <> Plug.Conn.Query.encode(@github_query_params)}
      target="_blank"
      class={[@class, "#{if @disabled, do: "bg-primary-300 cursor-not-allowed"}"]}
      {if @user.github_oauth_token, do: ["phx-hook": "Tooltip", "aria-label": "Your token has expired"], else: []}
    >
      {if @user.github_oauth_token, do: "Reconnect", else: "Connect"} your GitHub Account
    </.link>
    """
  end

  attr :class, :string, default: "mb-4", doc: "spacing classes for the banner"

  @doc """
  Blue info banner pointing to the GitHub sync docs. Shown inside each state of
  the Sync tab's GitHub panel.
  """
  def sync_docs_banner(assigns) do
    ~H"""
    <div
      id="github-sync-docs-banner"
      class={[
        "flex items-start gap-3 rounded-md border border-blue-200 bg-blue-50 p-3 text-sm text-black",
        @class
      ]}
    >
      <.icon name="hero-information-circle" class="h-5 w-5 shrink-0 text-blue-500" />
      <p>
        Learn more about synchronizing your project with GitHub at
        <.link
          target="_blank"
          href="https://docs.openfn.org/documentation/link-to-GitHub"
          class="font-medium underline"
        >
          docs.openfn.org
        </.link>
      </p>
    </div>
    """
  end

  defp build_query_params do
    config = Application.fetch_env!(:lightning, :github_app)
    client_id = Keyword.fetch!(config, :client_id)

    redirect_url = url(LightningWeb.Endpoint, ~p"/oauth/github/callback")

    %{client_id: client_id, redirect_uri: redirect_url}
  end
end
