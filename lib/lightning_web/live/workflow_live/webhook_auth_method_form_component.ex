defmodule LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias Phoenix.LiveView.JS

  @impl true
  def update(%{webhook_auth_method: webhook_auth_method} = assigns, socket) do
    changeset = WebhookAuthMethod.changeset(webhook_auth_method, %{})

    {:ok,
     socket
     |> assign(changeset: changeset)
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"webhook_auth_method" => params},
        socket
      ) do
    changeset =
      socket.assigns.webhook_auth_method
      |> WebhookAuthMethod.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "choose_auth_type",
        %{"webhook_auth_method" => params},
        socket
      ) do
    auth_method =
      socket.assigns.webhook_auth_method
      |> WebhookAuthMethod.changeset(params)
      |> Ecto.Changeset.apply_changes()

    auth_method =
      if auth_method.auth_type == :api do
        api_key = WebhookAuthMethod.generate_api_key()
        %{auth_method | api_key: api_key}
      else
        auth_method
      end

    {:noreply, assign(socket, :webhook_auth_method, auth_method)}
  end

  def handle_event("save", %{"webhook_auth_method" => params}, socket) do
    save_webhook_auth_method(socket, socket.assigns.action, params)
  end

  defp save_webhook_auth_method(socket, :edit, params) do
    case WebhookAuthMethods.update_auth_method(
           socket.assigns.webhook_auth_method,
           params
         ) do
      {:ok, _webhook_auth_method} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook credential updated successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_webhook_auth_method(
         %{
           assigns: %{
             trigger: %{} = trigger,
             webhook_auth_method: auth_method
           }
         } = socket,
         :new,
         params
       ) do
    params =
      Map.merge(params, %{
        "auth_type" => auth_method.auth_type,
        "api_key" => auth_method.api_key,
        "project_id" => auth_method.project_id
      })

    case WebhookAuthMethods.create_auth_method(trigger, params) do
      {:ok, _auth_method} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook auth method created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp save_webhook_auth_method(
         %{assigns: assigns} = socket,
         :new,
         params
       ) do
    params =
      Map.merge(params, %{
        "auth_type" => assigns.webhook_auth_method.auth_type,
        "api_key" => assigns.webhook_auth_method.api_key,
        "project_id" => assigns.webhook_auth_method.project_id
      })

    case WebhookAuthMethods.create_auth_method(params) do
      {:ok, _webhook_auth_method} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook auth method created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal id={@id} {assigns}>
        <:title>
          <div class="flex justify-between">
            <span :if={@action == :new}>
              <%= case @webhook_auth_method.auth_type do %>
                <% nil -> %>
                  Add an authentication method
                <% :basic -> %>
                  Create a Basic HTTP Credential
                <% :api -> %>
                  Create an API Credential
              <% end %>
            </span>
            <span :if={@action == :edit}>
              Edit webhook credential
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

        <div class="w-full bg-gray-100 h-0.5"></div>
        <:subtitle>
          <%= if @webhook_auth_method.auth_type && @action == :new do %>
            <span class="italic text-xs">
              Webhook authentication credentials are accessible to everyone within your project and can be managed via your settings here.
            </span>
          <% end %>
        </:subtitle>

        <%= if @webhook_auth_method.auth_type do %>
          <.form
            :let={f}
            id={"form_#{@id}"}
            for={@changeset}
            phx-submit="save"
            phx-target={@myself}
            class="mt-2"
          >
            <%= case @webhook_auth_method.auth_type do %>
              <% :basic -> %>
                <.input
                  type="text"
                  field={f[:name]}
                  label="Credential name"
                  required="true"
                />
                <.input
                  type="text"
                  field={f[:username]}
                  label="Username"
                  required="true"
                  disabled={@action == :edit}
                />
                <%= if @action == :edit do %>
                  <div class="mb-3">
                    <label class="block text-sm font-semibold leading-6 text-slate-800">
                      Password
                    </label>
                    <div class="mt-2 flex rounded-md shadow-sm">
                      <input
                        type="password"
                        id={f[:password].id}
                        value={f[:password].value}
                        class="block w-full rounded-l-lg text-slate-900 focus:ring-0 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 disabled:ring-gray-200 sm:text-sm sm:leading-6"
                        disabled="disabled"
                      />

                      <button
                        id={"#{f[:password].id}_copy_button"}
                        type="button"
                        phx-hook="Copy"
                        phx-then={
                          JS.show(%JS{}, to: "##{f[:password].id}_copied_alert")
                        }
                        data-to={"##{f[:password].id}"}
                        class="relative -ml-px inline-flex items-center gap-x-1.5 rounded-r-lg px-3 py-2 text-sm font-semibold text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                      >
                        Copy
                      </button>
                      <.copied_alert id={"#{f[:password].id}_copied_alert"} />
                    </div>
                  </div>
                <% else %>
                  <.input
                    type="password"
                    field={f[:password]}
                    label="Password"
                    required="true"
                  />
                <% end %>
              <% :api -> %>
                <.input
                  type="text"
                  field={f[:name]}
                  label="Credential name"
                  required="true"
                />

                <div class="mb-3">
                  <label class="block text-sm font-semibold leading-6 text-slate-800">
                    API Key
                  </label>
                  <div class="mt-2 flex rounded-md shadow-sm">
                    <input
                      type="text"
                      id={"api_key_#{@id}"}
                      class="block w-full rounded-l-lg text-slate-900 focus:ring-0 disabled:cursor-not-allowed disabled:bg-gray-50 disabled:text-gray-500 disabled:ring-gray-200 sm:text-sm sm:leading-6"
                      value={@webhook_auth_method.api_key}
                      disabled="disabled"
                    />

                    <button
                      id={"api_key_#{@id}_copy_button"}
                      type="button"
                      phx-hook="Copy"
                      phx-then={JS.show(%JS{}, to: "#api_key_#{@id}_copied_alert")}
                      data-to={"#api_key_#{@id}"}
                      class="relative -ml-px inline-flex items-center gap-x-1.5 rounded-r-lg px-3 py-2 text-sm font-semibold text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                    >
                      Copy
                    </button>
                    <.copied_alert id={"#{f[:password].id}_copied_alert"} />
                  </div>
                </div>
            <% end %>

            <div class="sm:flex sm:flex-row-reverse">
              <button
                type="submit"
                class="inline-flex w-full justify-center rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
              >
                <%= if @action == :new do %>
                  Create credential
                <% else %>
                  Save changes
                <% end %>
              </button>
              <button
                type="button"
                phx-click={hide_modal(@id)}
                class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
              >
                Cancel
              </button>
            </div>
          </.form>
        <% else %>
          <.form
            :let={f}
            id={"form_#{@id}"}
            for={@changeset}
            phx-change="validate"
            phx-submit="choose_auth_type"
            phx-target={@myself}
          >
            <div class="space-y-4">
              <label class={[
                "relative block cursor-pointer rounded-lg border bg-white px-6 py-4 shadow-sm focus:outline-none",
                if(
                  Phoenix.HTML.Form.input_value(f, :auth_type) == :basic,
                  do: "border-indigo-600 ring-2 ring-indigo-600",
                  else: "border-gray-300"
                )
              ]}>
                <%= Phoenix.HTML.Form.radio_button(f, :auth_type, :basic,
                  class: "sr-only"
                ) %>
                <span class="flex items-center gap-2">
                  <Heroicons.globe_alt solid class="h-5 w-5" />
                  Basic HTTP Authentication (username & password)
                </span>
                <span
                  class={[
                    "pointer-events-none absolute -inset-px rounded-lg",
                    if(Phoenix.HTML.Form.input_value(f, :auth_type) == :basic,
                      do: "border-indigo-600",
                      else: "border-transparent"
                    )
                  ]}
                  aria-hidden="true"
                >
                </span>
              </label>

              <label class={[
                "relative block cursor-pointer rounded-lg border bg-white px-6 py-4 shadow-sm focus:outline-none",
                if(Phoenix.HTML.Form.input_value(f, :auth_type) == :api,
                  do: "border-indigo-600 ring-2 ring-indigo-600",
                  else: "border-gray-300"
                )
              ]}>
                <%= Phoenix.HTML.Form.radio_button(f, :auth_type, :api,
                  class: "sr-only"
                ) %>
                <span class="flex items-center gap-2">
                  <Heroicons.code_bracket_square solid class="h-5 w-5" />
                  API Key Authentication (‘x-api-key’ header)
                </span>
                <span
                  class={[
                    "pointer-events-none absolute -inset-px rounded-lg",
                    if(Phoenix.HTML.Form.input_value(f, :auth_type) == :api,
                      do: "border-indigo-600",
                      else: "border-transparent"
                    )
                  ]}
                  aria-hidden="true"
                >
                </span>
              </label>
            </div>
            <div class="py-3">
              <button
                type="submit"
                class="inline-flex w-full justify-center rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 "
              >
                Next
              </button>
            </div>
          </.form>
        <% end %>
      </.modal>
    </div>
    """
  end

  defp copied_alert(assigns) do
    ~H"""
    <div id={@id} class="hidden rounded-md bg-green-50 p-2" phx-hook="Flash">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-green-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <span class="ml-1 p-1 text-xs font-semibold text-green-800">
          Copied!
        </span>
      </div>
    </div>
    """
  end
end
