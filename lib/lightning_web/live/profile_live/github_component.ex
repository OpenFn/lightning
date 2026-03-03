defmodule LightningWeb.ProfileLive.GithubComponent do
  @moduledoc false

  use LightningWeb, :live_component
  alias Lightning.VersionControl
  alias LightningWeb.Components.GithubComponents

  @impl true
  def update(%{user: _user} = assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("disconnect-github", _params, socket) do
    case VersionControl.delete_github_oauth_grant(socket.assigns.user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "GitHub connection removed successfully")
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
    <div class="bg-white shadow-xs ring-1 ring-gray-900/5 sm:rounded-xl md:col-span-2 mb-4">
      <div class="px-4 py-6 sm:p-8">
        <div class="flex items-center justify-between mb-5 gap-5">
          <span class="flex flex-grow flex-col">
            <span
              class="text-xl font-medium leading-6 text-gray-900"
              id={"#{@id}-label"}
            >
              GitHub Access
            </span>
            <span class="text-sm text-gray-500" id={"#{@id}-description"}>
              Linking your OpenFn account to your GitHub account allows you to manage version control across your projects.
            </span>
          </span>
          <%= if oauth_enabled?() do %>
            <%= if token_valid?(@user.github_oauth_token) do %>
              <.button
                id="disconnect-github-button"
                type="button"
                phx-click={show_modal("disconnect_github_modal")}
                theme="danger"
              >
                Disconnect from GitHub
              </.button>
              <.confirm_github_disconnection_modal
                id="disconnect_github_modal"
                myself={@myself}
              />
            <% else %>
              <GithubComponents.connect_to_github_link
                id="connect-github-link"
                user={@user}
              />
            <% end %>
          <% else %>
            <.button
              id="github-oauth-not-enabled"
              type="button"
              theme="primary"
              disabled={true}
              tooltip="GitHub OAuth has not been enabled for this instance."
            >
              Connect your GitHub account
            </.button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp oauth_enabled? do
    VersionControl.github_enabled?()
  end

  defp token_valid?(token) do
    VersionControl.oauth_token_valid?(token)
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
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <p class="text-sm text-gray-500">
        You are about to disconnect your OpenFn account from GitHub.
        Until you reconnect, you will not be able to set up or modify version control for your projects.
      </p>
      <.modal_footer>
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          theme="danger"
          phx-disable-with="Disconnecting..."
          phx-click="disconnect-github"
          phx-target={@myself}
        >
          Disconnect
        </.button>
        <.button type="button" phx-click={hide_modal(@id)} theme="secondary">
          Cancel
        </.button>
      </.modal_footer>
    </.modal>
    """
  end
end
