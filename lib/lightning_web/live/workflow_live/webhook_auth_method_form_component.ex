defmodule LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias Phoenix.LiveView.JS

  @impl true
  def update(
        %{webhook_auth_method: webhook_auth_method, current_user: _user} =
          assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(:changeset, WebhookAuthMethod.changeset(webhook_auth_method, %{}))
     |> assign(:delete_confirmation_changeset, delete_confirmation_changeset())
     |> assign(assigns)}
  end

  def delete_confirmation_changeset(params \\ %{}) do
    {%{confirmation: ""}, %{confirmation: :string}}
    |> Ecto.Changeset.cast(
      params,
      [:confirmation]
    )
    |> Ecto.Changeset.validate_required([:confirmation],
      message: "Please type 'DELETE' to confirm"
    )
    |> Ecto.Changeset.validate_inclusion(:confirmation, ["DELETE"],
      message: "Please type 'DELETE' to confirm"
    )
  end

  @impl true
  def handle_event("save", %{"webhook_auth_method" => params}, socket) do
    save_webhook_auth_method(socket, socket.assigns.action, params)
  end

  def handle_event(
        "validate_deletion",
        %{"delete_confirmation_changeset" => delete_confirmation_changeset},
        socket
      ) do
    changeset =
      delete_confirmation_changeset(delete_confirmation_changeset)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:delete_confirmation_changeset, changeset)}
  end

  def handle_event(
        "perform_deletion",
        %{"delete_confirmation_changeset" => delete_confirmation_changeset},
        socket
      ) do
    changeset =
      delete_confirmation_changeset(delete_confirmation_changeset)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      case WebhookAuthMethods.schedule_for_deletion(
             socket.assigns.webhook_auth_method
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Webhook autehntication method scheduled for deletion successfully"
           )
           |> push_navigate(to: socket.assigns.return_to)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:noreply, socket |> assign(:delete_confirmation_changeset, changeset)}
    end
  end

  defp save_webhook_auth_method(socket, :edit, params) do
    case WebhookAuthMethods.update_auth_method(
           socket.assigns.webhook_auth_method,
           params,
           actor: socket.assigns.current_user
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
         %{assigns: %{trigger: %_{}} = assigns} = socket,
         :new,
         params
       ) do
    enriched_params = enrich_params(params, assigns.webhook_auth_method)

    case WebhookAuthMethods.create_auth_method(assigns.trigger, enriched_params,
           actor: assigns.current_user
         ) do
      {:ok, _auth_method} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook auth method created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp save_webhook_auth_method(%{assigns: assigns} = socket, :new, params) do
    enriched_params = enrich_params(params, socket.assigns.webhook_auth_method)

    case WebhookAuthMethods.create_auth_method(enriched_params,
           actor: assigns.current_user
         ) do
      {:ok, _webhook_auth_method} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook auth method created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp enrich_params(params, webhook_auth_method) do
    Map.merge(params, %{
      "auth_type" => webhook_auth_method.auth_type,
      "api_key" => webhook_auth_method.api_key,
      "project_id" => webhook_auth_method.project_id
    })
  end

  @impl true
  def render(%{action: :delete} = assigns) do
    ~H"""
    <div>
      <.form
        :let={f}
        id={"delete_auth_method_#{@id}"}
        for={@delete_confirmation_changeset}
        as={:delete_confirmation_changeset}
        phx-change="validate_deletion"
        phx-submit="perform_deletion"
        phx-target={@myself}
      >
        <div class="space-y-4">
          <%= if @webhook_auth_method.triggers |> Enum.count() == 0 do %>
            <p>You are about to delete the webhook credential
              "<span class="font-bold"><%= @webhook_auth_method.name %></span>"
              which is used by no workflows.</p>
          <% else %>
            <p>
              You are about to delete the webhook credential
              "<span class="font-bold"><%= @webhook_auth_method.name %></span>"
              which is used by <span class="mb-2 text-purple-600 underline cursor-pointer"><%= @webhook_auth_method.triggers |> Enum.count() %> workflow triggers</span>.
            </p>
            <p>
              Deleting this webhook will remove it from any associated triggers and cannot be undone.
            </p>
          <% end %>

          <.label for={:confirmation}>
            Type in 'DELETE' to confirm the deletion
          </.label>
          <.input type="text" field={f[:confirmation]} />
        </div>
        <div class="sm:flex sm:flex-row-reverse">
          <button
            id="delete_trigger_auth_methods_button"
            type="submit"
            phx-disable-with="Deleting..."
            class="inline-flex w-full justify-center rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 sm:ml-3 sm:w-auto focus:ring-red-500 bg-red-600 hover:bg-red-700 disabled:bg-red-300"
            disabled={!@delete_confirmation_changeset.valid?}
          >
            Delete authentication method
          </button>
          <button
            type="button"
            phx-click={JS.navigate(@return_to)}
            class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
          >
            Cancel
          </button>
        </div>
      </.form>
    </div>
    """
  end

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
