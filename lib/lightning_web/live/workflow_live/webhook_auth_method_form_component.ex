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
                      data-to={"##{f[:password].id}"}
                      class="relative -ml-px inline-flex items-center gap-x-1.5 rounded-r-lg px-3 py-2 text-sm font-semibold text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                    >
                      Copy
                    </button>
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
                    data-to={"#api_key_#{@id}"}
                    class="relative -ml-px inline-flex items-center gap-x-1.5 rounded-r-lg px-3 py-2 text-sm font-semibold text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
                  >
                    Copy
                  </button>
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
              phx-click={JS.navigate(@return_to)}
              class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
            >
              Cancel
            </button>
          </div>
        </.form>
      <% end %>
    </div>
    """
  end
end
