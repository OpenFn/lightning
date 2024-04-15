defmodule LightningWeb.CredentialLive.GenericOauthComponent do
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper

  alias Lightning.OauthClients
  alias LightningWeb.Components.NewInputs

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok, socket |> assign(:selected_client, nil) |> assign(:scopes, [])}
  end

  @impl true
  def handle_event(
        "oauth_client_change",
        %{"credential" => %{"client_id" => client_id}},
        socket
      ) do
    client =
      if client_id === "", do: nil, else: OauthClients.get_client!(client_id)

    {:noreply, socket |> assign(:selected_client, client)}
  end

  def handle_event("add_scope", %{"key" => key, "value" => value}, socket) do
    case key do
      "," ->
        scope_to_add = String.trim_trailing(value, key)
        new_scopes = [scope_to_add | socket.assigns.scopes] |> Enum.reverse()

        {:noreply,
         socket |> assign(:scopes, new_scopes) |> push_event("clear_input", %{})}

      "Backspace" ->
        new_scopes = List.pop_at(socket.assigns.scopes, -1)
        {:noreply, socket |> assign(:scopes, new_scopes)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_scope", %{"scope" => scope_to_remove}, socket) do
    new_scopes =
      Enum.reject(socket.assigns.scopes, fn scope ->
        scope == scope_to_remove
      end)

    {:noreply, assign(socket, scopes: new_scopes)}
  end

  attr :form, :map, required: true
  attr :clients, :list, required: true
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    assigns = assigns |> assign(valid?: changeset.valid?)

    ~H"""
    <%= render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &live_component/1,
         [
           module: __MODULE__,
           form: @form,
           clients: @clients,
           id: "generic-oauth-component"
         ],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    ) %>
    """
  end

  @impl true
  def render(%{clients: []} = assigns) do
    ~H"""
    <div class="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-12 text-center focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2">
      <svg
        class="mx-auto h-12 w-12 text-gray-400"
        stroke="currentColor"
        fill="none"
        viewBox="0 0 48 48"
        aria-hidden="true"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
        />
      </svg>
      <span class="mt-2 block text-sm font-medium text-gray-900">
        No OAuth Client found.
        <br />Please create one before configuring a Generic OAuth2 credential.
      </span>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="space-y-4 mt-5">
        <NewInputs.input
          type="select"
          options={Enum.map(@clients, &{&1.name, &1.id})}
          field={@form[:client_id]}
          prompt=""
          phx-change="oauth_client_change"
          phx-target={@myself}
          label="Select a client"
          required="true"
        />
        <span :if={@selected_client}>
          Instance URL: <%= @selected_client.base_url %>
        </span>
      </div>
      <div class="space-y-2 mt-5">
        <NewInputs.label>Scopes</NewInputs.label>
        <div class="flex flex-wrap items-center border border-gray-300 rounded-lg p-2">
          <div class="flex flex-wrap gap-2">
            <span
              :for={scope <- @scopes}
              class="inline-flex items-center gap-x-0.5 rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"
            >
              <%= scope %>
              <button
                type="button"
                phx-click="remove_scope"
                phx-value-scope={scope}
                phx-target={@myself}
                class="group relative -mr-1 h-3.5 w-3.5 rounded-sm hover:bg-gray-500/20"
              >
                <span class="sr-only">Remove</span>
                <svg
                  viewBox="0 0 14 14"
                  class="h-3.5 w-3.5 stroke-gray-600/50 group-hover:stroke-gray-600/75"
                >
                  <path d="M4 4l6 6m0-6l-6 6" />
                </svg>
                <span class="absolute -inset-1"></span>
              </button>
            </span>
          </div>
          <input
            id="scopes-tag-input"
            class="flex-1 border-none focus:ring-0"
            type="text"
            name="scope"
            phx-window-keyup="add_scope"
            phx-target={@myself}
            phx-hook="ClearInput"
            placeholder="Separate multiple scopes with a comma"
          />
        </div>
      </div>
      <div class="space-y-4 mt-5">
        <NewInputs.input type="text" field={@form[:state]} label="State" />
      </div>
      <div class="space-y-4 mt-5">
        <NewInputs.input type="text" field={@form[:api_version]} label="API Version" />
      </div>
    </div>
    """
  end
end
