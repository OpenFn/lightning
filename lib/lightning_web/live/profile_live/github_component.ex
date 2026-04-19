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
           "Oops! An error occurred while trying to remove the connection. Please try again"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white p-4 rounded-md space-y-4">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h6 class="font-medium text-black" id={"#{@id}-label"}>
            GitHub access
          </h6>
          <small class="block my-1 text-xs text-gray-600" id={"#{@id}-description"}>
            Link your OpenFn account to GitHub to manage version control across your projects.
          </small>
        </div>
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
