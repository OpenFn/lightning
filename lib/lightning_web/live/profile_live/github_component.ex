defmodule LightningWeb.ProfileLive.GithubComponent do
  @moduledoc false

  use LightningWeb, :live_component
  alias Lightning.VersionControl

  @impl true
  def update(%{user: _user} = assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("disconnect-github", _params, socket) do
    case VersionControl.delete_github_ouath_grant(socket.assigns.user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Github connection removed successfully")
         |> push_navigate(to: ~p"/profile")}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Oops! An error occured while trying to remove the connection. Please try again"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow-sm ring-1 ring-gray-900/5 sm:rounded-xl md:col-span-2 mb-4">
      <div class="px-4 py-6 sm:p-8">
        <div class="flex items-center justify-between mb-5 gap-5">
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
          <%= if token_valid?(@user.github_oauth_token) do %>
            <.button
              id="disconnect-github-button"
              type="button"
              phx-click={show_modal("disconnect_github_modal")}
              color_class="text-white bg-danger-500 hover:bg-danger-700"
            >
              Disconnect from Github
            </.button>
            <.confirm_github_disconnection_modal
              id="disconnect_github_modal"
              myself={@myself}
            />
          <% else %>
            <.link
              id="connect-github-link"
              href={"https://github.com/login/oauth/authorize?" <> build_query_params(@socket)}
              target="_blank"
              class="text-center py-2 px-4 shadow-sm text-sm font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 bg-primary-600 hover:bg-primary-700 text-white"
              {if @user.github_oauth_token, do: ["phx-hook": "Tooltip", "aria-label": "Your token has expired"], else: []}
            >
              <%= if @user.github_oauth_token, do: "Reconnect", else: "Connect" %> your Github Account
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp token_valid?(token) do
    VersionControl.oauth_token_valid?(token)
  end

  defp build_query_params(socket) do
    client_id =
      Application.get_env(:lightning, :github_app, [])
      |> Keyword.get(:client_id, nil)

    redirect_url = Routes.oauth_url(socket, :new, "github")

    params = %{client_id: client_id, redirect_uri: redirect_url}

    Plug.Conn.Query.encode(params)
  end

  defp confirm_github_disconnection_modal(assigns) do
    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Disconnect from GitHub?
          </span>
          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="px-6">
        <p class="text-sm text-gray-500">
          You are about to disconnect your OpenFn account from GitHub.
          Until you reconnect, you will not be able to set up or modify version control for your projects.
        </p>
      </div>
      <div class="flex flex-row-reverse gap-4 mx-6 mt-2">
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          color_class="bg-red-600 hover:bg-red-700 text-white"
          phx-disable-with="Disconnecting..."
          phx-click="disconnect-github"
          phx-target={@myself}
        >
          Disconnect
        </.button>
        <button
          type="button"
          phx-click={hide_modal(@id)}
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end
end
