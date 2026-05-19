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
        <LightningWeb.Components.SsoIcons.provider_icon
          name={@provider.name}
          class="h-6 w-6 text-gray-700"
        />
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

  defp display_name(provider), do: String.capitalize(provider)
end
