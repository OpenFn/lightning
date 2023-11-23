defmodule LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent do
  @moduledoc false

  alias Lightning.Projects.Project
  use LightningWeb, :live_component

  alias Lightning.Accounts
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
     |> assign(assigns)
     |> assign(sudo_mode?: false)
     |> assign(show_2fa_options: false)}
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

  def handle_event("toggle-2fa", _params, %{assigns: assigns} = socket) do
    {:noreply,
     assign(socket, show_2fa_options: !assigns.show_2fa_options, error_msg: nil)}
  end

  def handle_event("reauthenticate-user", %{"user" => params}, socket) do
    current_user = socket.assigns.current_user

    if valid_user_input?(current_user, params) do
      {:noreply,
       assign(socket, sudo_mode?: true, show_2fa_options: false, error_msg: nil)}
    else
      {:noreply, assign(socket, error_msg: "Invalid! Please try again")}
    end
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
        "validate",
        %{"webhook_auth_method" => params},
        socket
      ) do
    enriched_params =
      enrich_params(params, socket.assigns.webhook_auth_method)
      |> slugify_username()

    changeset =
      WebhookAuthMethod.changeset(
        socket.assigns.webhook_auth_method,
        enriched_params
      )

    changeset =
      WebhookAuthMethods.list_for_project(%Project{
        id: socket.assigns.webhook_auth_method.project_id
      })
      |> Enum.any?(fn wam -> wam.name == params["name"] end)
      |> if do
        Ecto.Changeset.add_error(
          changeset,
          :name,
          "must be unique within the project"
        )
      else
        changeset
      end
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset)}
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
             socket.assigns.webhook_auth_method,
             actor: socket.assigns.current_user
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Your Webhook Authentication method has been deleted."
           )
           |> push_navigate(to: socket.assigns.return_to)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:noreply, socket |> assign(:delete_confirmation_changeset, changeset)}
    end
  end

  defp slugify_username(%{"username" => username} = params),
    do: %{
      params
      | "username" => username |> String.downcase() |> String.replace(" ", "-")
    }

  defp slugify_username(params), do: params

  defp save_webhook_auth_method(socket, :edit, params) do
    case WebhookAuthMethods.update_auth_method(
           socket.assigns.webhook_auth_method,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _webhook_auth_method} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook auth method updated successfully")
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

  defp valid_user_input?(current_user, %{"password" => password, "code" => code}) do
    Accounts.User.valid_password?(current_user, password) ||
      Accounts.valid_user_totp?(current_user, code)
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
        <div class="space-y-4 ml-[24px] mr-[24px]">
          <%= if @webhook_auth_method.triggers |> Enum.count() == 0 do %>
            <p>You are about to delete the webhook auth method
              "<span class="font-bold"><%= @webhook_auth_method.name %></span>"
              which is used by no workflows.</p>
          <% else %>
            <p>
              You are about to delete the webhook auth method
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
        <.modal_footer class="mx-6 mt-6">
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
        </.modal_footer>
      </.form>
    </div>
    """
  end

  def render(%{action: :edit, show_2fa_options: true} = assigns) do
    ~H"""
    <div>
      <.form
        :let={f}
        for={%{}}
        action="#"
        phx-submit="reauthenticate-user"
        as={:user}
        phx-target={@myself}
        class="mt-2"
        id="reauthentication-form"
      >
        <div class="space-y-4 ml-[24px] mr-[24px]">
          <p class="font-normal text-sm whitespace-normal">
            You're required to reauthenticate yourself before viewing the webhook
            <%= if @webhook_auth_method.auth_type == :basic do %>
              Password
            <% else %>
              API Key
            <% end %>
          </p>
          <%= if @error_msg do %>
            <div class="alert alert-danger" role="alert">
              <%= @error_msg %>
            </div>
          <% end %>

          <.input type="password" field={f[:password]} label="Password" />
          <div class="relative">
            <div class="absolute inset-0 flex items-center" aria-hidden="true">
              <div class="w-full border-t border-gray-300"></div>
            </div>
            <div class="relative flex justify-center">
              <span class="bg-white px-2 text-sm text-gray-500">OR</span>
            </div>
          </div>
          <.input type="text" field={f[:code]} label="2FA Code" inputmode="numeric" />
        </div>
        <.modal_footer class="mx-6 mt-6">
          <div class="sm:flex sm:flex-row-reverse">
            <button
              type="submit"
              class="inline-flex w-full justify-center rounded-md bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
            >
              Done
            </button>
            <button
              type="button"
              phx-click="toggle-2fa"
              phx-target={@myself}
              class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
            >
              Cancel
            </button>
          </div>
        </.modal_footer>
      </.form>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id="create_edit_webhook_auth_method">
      <%!-- <%= if @webhook_auth_method.auth_type do %> --%>
      <.form
        :let={f}
        id={"form_#{@id}"}
        for={@changeset}
        phx-submit="save"
        phx-change="validate"
        phx-target={@myself}
      >
        <div class="ml-[24px] mr-[24px]">
          <%= case @webhook_auth_method.auth_type do %>
            <% :basic -> %>
              <.label for={:name}>Auth method name</.label>
              <.input type="text" field={f[:name]} required="true" />

              <div class="hidden sm:block" aria-hidden="true">
                <div class="py-1"></div>
              </div>

              <.label for={:username}>Username</.label>
              <.input
                type="text"
                field={f[:username]}
                required="true"
                disabled={@action == :edit}
              />

              <div class="hidden sm:block" aria-hidden="true">
                <div class="py-1"></div>
              </div>

              <%= if @action == :edit do %>
                <div class="mb-3">
                  <label class="block text-sm font-semibold leading-6 text-slate-800">
                    Password
                  </label>
                  <.maybe_mask_password_field
                    field={f[:password]}
                    sudo_mode?={@sudo_mode?}
                    phx_target={@myself}
                  />
                </div>
              <% else %>
                <.label for={:password}>Password</.label>
                <.input type="password" field={f[:password]} required="true" />

                <div class="hidden sm:block" aria-hidden="true">
                  <div class="py-1"></div>
                </div>
              <% end %>
            <% :api -> %>
              <.label for={:name}>Auth method name</.label>
              <.input type="text" field={f[:name]} required="true" />

              <div class="hidden sm:block" aria-hidden="true">
                <div class="py-1"></div>
              </div>

              <.label for={:api_key}>API Key</.label>
              <.maybe_mask_api_key_field
                action={@action}
                field={f[:api_key]}
                sudo_mode?={@sudo_mode?}
                phx_target={@myself}
              />
          <% end %>
        </div>
        <.modal_footer class="mx-6 mt-6">
          <div class="sm:flex sm:flex-row-reverse">
            <button
              type="submit"
              disabled={!@changeset.valid?}
              class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
            >
              <%= if @action == :new do %>
                Create auth method
              <% else %>
                Save changes
              <% end %>
            </button>
            <.cancel_button return_to={@return_to} />
          </div>
        </.modal_footer>
      </.form>
      <%!-- <% end %> --%>
    </div>
    """
  end

  defp cancel_button(assigns) do
    view = assigns.return_to |> String.split("/") |> List.last()

    if view == "settings#webhook_security" do
      ~H"""
      <button
        type="button"
        phx-click={JS.navigate(@return_to)}
        class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
      >
        Cancel
      </button>
      """
    else
      ~H"""
      <button
        type="button"
        phx-click="close_webhook_modal"
        phx-target="#webhooks_auth_method_modal-container"
        class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
      >
        Cancel
      </button>
      """
    end
  end

  attr :field, :map, required: true
  attr :phx_target, :any, required: true
  attr :sudo_mode?, :boolean, required: true

  defp maybe_mask_password_field(assigns) do
    ~H"""
    <div>
      <div class="mt-2 flex rounded-md shadow-sm">
        <input
          type="password"
          id={@field.id}
          value={
            if(@sudo_mode?, do: @field.value, else: mask_password(@field.value))
          }
          class="block w-full flex-1 rounded-l-lg text-slate-900 disabled:bg-gray-50 disabled:text-gray-500 border border-r-0 border-secondary-300 sm:text-sm sm:leading-6"
          disabled="disabled"
        />

        <button
          id={"#{@field.id}_action_button"}
          type="button"
          class="w-[100px] inline-block relative rounded-r-lg px-3 text-sm font-normal text-gray-900 border border-secondary-300 hover:bg-gray-50"
          {if(@sudo_mode?, do: ["phx-hook": "Copy", "data-to": "##{@field.id}"], else: ["phx-click": "toggle-2fa", "phx-target": @phx_target])}
        >
          <%= if @sudo_mode? do %>
            Copy
          <% else %>
            Show
          <% end %>
        </button>
      </div>
      <div class="h-6"></div>
      <div class="hidden sm:block" aria-hidden="true">
        <div class="py-1"></div>
      </div>
    </div>
    """
  end

  defp mask_password(value) do
    value
    |> String.graphemes()
    |> Enum.map_join(fn _char -> "*" end)
  end

  attr :field, :map, required: true
  attr :phx_target, :any, required: true
  attr :sudo_mode?, :boolean, required: true
  attr :action, :any, required: true

  defp maybe_mask_api_key_field(assigns) do
    ~H"""
    <div>
      <div class="mt-2 flex rounded-md shadow-sm">
        <input
          type="text"
          id={@field.id}
          class="block w-full flex-1 rounded-l-lg text-slate-900 disabled:bg-gray-50 disabled:text-gray-500 border border-r-0 border-secondary-300 sm:text-sm sm:leading-6"
          value={
            if(@action == :new || @sudo_mode?,
              do: @field.value,
              else: mask_api_key(@field.value)
            )
          }
          disabled="disabled"
        />

        <button
          id={"#{@field.id}_action_button"}
          type="button"
          class="w-[100px] inline-block relative rounded-r-lg px-3 text-sm font-normal text-gray-900 border border-secondary-300 hover:bg-gray-50"
          {if(@action == :new || @sudo_mode?, do: ["phx-hook": "Copy", "data-to": "##{@field.id}"], else: ["phx-click": "toggle-2fa", "phx-target": @phx_target])}
        >
          <%= if @action == :new || @sudo_mode? do %>
            Copy
          <% else %>
            Show
          <% end %>
        </button>
      </div>
      <div class="h-6"></div>
      <div class="hidden sm:block" aria-hidden="true">
        <div class="py-1"></div>
      </div>
    </div>
    """
  end

  defp mask_api_key(value) do
    {last_5, first_n} =
      value |> String.graphemes() |> Enum.reverse() |> Enum.split(5)

    masked_n = first_n |> Enum.take(15) |> Enum.map(fn _char -> "*" end)

    (last_5 ++ masked_n)
    |> Enum.reverse()
    |> Enum.join()
  end
end
