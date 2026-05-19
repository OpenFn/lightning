defmodule LightningWeb.ProfileLive.IdentitiesComponent do
  @moduledoc """
  Component to manage linked SSO identities on a User's profile.
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts
  alias Lightning.AuthProviders

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_providers(user)}
  end

  @impl true
  def handle_event("unlink-identity", %{"provider" => provider}, socket) do
    case Accounts.unlink_user_identity(socket.assigns.user, provider) do
      {:ok, _identity} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Unlinked your #{display_name(provider)} account."
         )
         |> push_navigate(to: ~p"/profile")}

      {:error, :would_lock_out} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Set a password (via the password reset link) before unlinking your only sign-in method."
         )}

      {:error, :not_linked} ->
        {:noreply,
         socket
         |> put_flash(:error, "That identity is not linked to your account.")
         |> push_navigate(to: ~p"/profile")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Could not unlink your #{display_name(provider)} account."
         )}
    end
  end

  defp assign_providers(socket, user) do
    {:ok, handlers} = AuthProviders.get_handlers()
    identities = Accounts.list_user_identities(user)

    linked_by_provider =
      Map.new(identities, fn identity -> {identity.provider, identity} end)

    providers =
      handlers
      |> Enum.map(fn handler ->
        %{
          name: handler.name,
          identity: Map.get(linked_by_provider, handler.name)
        }
      end)
      |> Enum.sort_by(& &1.name)

    assign(socket, providers: providers)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow-xs ring-1 ring-gray-900/5 sm:rounded-xl md:col-span-2 mb-4">
      <div class="px-4 py-6 sm:p-8">
        <div class="mb-5">
          <span
            class="text-xl font-medium leading-6 text-gray-900"
            id={"#{@id}-label"}
          >
            Single Sign-On
          </span>
          <p class="text-sm text-gray-500 mt-1" id={"#{@id}-description"}>
            Link your account to an SSO provider so you can sign in without a password.
          </p>
        </div>

        <%= if @providers == [] do %>
          <p class="text-sm text-gray-500 italic">
            No SSO providers are configured for this instance.
          </p>
        <% else %>
          <ul role="list" class="divide-y divide-gray-200">
            <%= for provider <- @providers do %>
              <.provider_row id={@id} provider={provider} myself={@myself} />
            <% end %>
          </ul>
        <% end %>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :provider, :map, required: true
  attr :myself, :any, required: true

  defp provider_row(assigns) do
    ~H"""
    <li
      id={"#{@id}-#{@provider.name}"}
      class="flex items-center justify-between py-4 gap-4"
    >
      <div class="flex items-center gap-3 min-w-0">
        <.provider_icon name={@provider.name} />
        <div class="min-w-0">
          <p class="text-sm font-medium text-gray-900 capitalize">
            {display_name(@provider.name)}
          </p>
          <%= if @provider.identity do %>
            <p class="text-xs text-gray-500 truncate">
              Linked · uid {@provider.identity.uid}
            </p>
          <% else %>
            <p class="text-xs text-gray-500">Not linked</p>
          <% end %>
        </div>
      </div>
      <div class="shrink-0">
        <%= if @provider.identity do %>
          <.button
            id={"unlink-#{@provider.name}-button"}
            type="button"
            theme="danger"
            phx-click="unlink-identity"
            phx-value-provider={@provider.name}
            phx-target={@myself}
            data-confirm={"Unlink #{display_name(@provider.name)} from your account?"}
          >
            Unlink
          </.button>
        <% else %>
          <.button_link
            id={"link-#{@provider.name}-button"}
            theme="secondary"
            href={~p"/authenticate/#{@provider.name}/link"}
          >
            Link
          </.button_link>
        <% end %>
      </div>
    </li>
    """
  end

  attr :name, :string, required: true

  defp provider_icon(%{name: "github"} = assigns) do
    ~H"""
    <svg
      class="h-6 w-6 text-gray-700"
      viewBox="0 0 16 16"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
    </svg>
    """
  end

  defp provider_icon(assigns) do
    ~H"""
    <.icon name="hero-identification" class="h-6 w-6 text-gray-700" />
    """
  end

  defp display_name(provider), do: String.capitalize(provider)
end
