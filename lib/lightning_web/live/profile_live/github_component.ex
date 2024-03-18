defmodule LightningWeb.ProfileLive.GithubComponent do
  @moduledoc """
  Component to enable MFA on a User's account
  """
  use LightningWeb, :live_component

  @impl true
  def update(%{user: _user} = assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow-sm ring-1 ring-gray-900/5 sm:rounded-xl md:col-span-2 mb-4">
      <div class="px-4 py-6 sm:p-8">
        <div class="flex items-center justify-between mb-5">
          <span class="flex flex-grow flex-col">
            <span
              class="text-xl font-medium leading-6 text-gray-900"
              id={"#{@id}-label"}
            >
              Github Access
            </span>
            <span class="text-sm text-gray-500" id={"#{@id}-description"}>
              Linking your OpenFn account to your Github account allows you to manage version control across your projects.
            </span>
          </span>
          <%= if @user.github_oauth_token do %>
            <.button>Disconnect from Github</.button>
          <% else %>
            <.link
              href={"https://github.com/login/oauth/authorize?" <> build_query_params(@socket)}
              target="_blank"
              class="text-center py-2 px-4 shadow-sm text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 bg-primary-600 hover:bg-primary-700 text-white"
            >
              Connect your Github Account
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp build_query_params(socket) do
    client_id =
      Application.get_env(:lightning, :github_app, [])
      |> Keyword.get(:client_id, nil)

    redirect_url = Routes.oauth_url(socket, :new, "github")

    params = %{client_id: client_id, redirect_uri: redirect_url}

    Plug.Conn.Query.encode(params)
  end
end
