defmodule LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Accounts
  alias Lightning.Projects.Project
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod

  @impl true
  def update(
        %{
          webhook_auth_method: webhook_auth_method,
          current_user: _user,
          on_close: _on_close,
          return_to: _return_to
        } =
          assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(:changeset, WebhookAuthMethod.changeset(webhook_auth_method, %{}))
     |> assign(
       :project_webhook_auth_methods,
       WebhookAuthMethods.list_for_project(%Project{
         id: webhook_auth_method.project_id
       })
     )
     |> assign(assigns)
     |> assign(sudo_mode?: false)
     |> assign(show_2fa_options: false)
     |> assign_new(:on_save, fn _ -> nil end)}
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
        "validate_auth_type",
        %{"webhook_auth_method" => params},
        socket
      ) do
    changeset =
      socket.assigns.webhook_auth_method
      |> WebhookAuthMethod.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event(
        "choose_auth_type",
        %{"webhook_auth_method" => params},
        socket
      ) do
    auth_method =
      WebhookAuthMethods.build(
        socket.assigns.webhook_auth_method,
        params
      )

    changeset = WebhookAuthMethod.changeset(auth_method, %{})

    {:noreply,
     assign(socket, webhook_auth_method: auth_method, changeset: changeset)}
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
      changeset
      |> Ecto.Changeset.validate_change(:name, fn :name, name ->
        if name in socket.assigns.project_webhook_auth_methods do
          [name: "must be unique within the project"]
        else
          []
        end
      end)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(changeset: changeset)}
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
      {:ok, webhook_auth_method} ->
        if socket.assigns.on_save do
          socket.assigns.on_save.(webhook_auth_method)
        end

        socket
        |> put_flash(:info, "Webhook auth method updated successfully")
        |> maybe_return_to()
        |> noreply()

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
      {:ok, auth_method} ->
        if socket.assigns.on_save do
          socket.assigns.on_save.(auth_method)
        end

        socket
        |> put_flash(:info, "Webhook auth method created successfully")
        |> maybe_return_to()
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp save_webhook_auth_method(%{assigns: assigns} = socket, :new, params) do
    enriched_params = enrich_params(params, socket.assigns.webhook_auth_method)

    case WebhookAuthMethods.create_auth_method(enriched_params,
           actor: assigns.current_user
         ) do
      {:ok, webhook_auth_method} ->
        if socket.assigns.on_save do
          socket.assigns.on_save.(webhook_auth_method)
        end

        socket
        |> put_flash(:info, "Webhook auth method created successfully")
        |> maybe_return_to()
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp maybe_return_to(socket) do
    if socket.assigns.return_to do
      push_patch(socket, to: socket.assigns.return_to)
    else
      socket
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
  slot :subtitle
  slot :action_buttons

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal_title>
        <div class="flex justify-between">
          <span>
            <%= if @action == :new do %>
              <%= case @webhook_auth_method.auth_type do %>
                <% nil -> %>
                  Add an authentication method
                <% :basic -> %>
                  Create a "basic auth" method
                <% :api -> %>
                  Create an "API token" method
              <% end %>
            <% else %>
              Webhook Authentication Method
            <% end %>
          </span>
          <button
            phx-click={@on_close}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
        <:subtitle>
          {render_slot(@subtitle)}
        </:subtitle>
      </.modal_title>
      <div class="my-[16px]"></div>
      <%= if @action in [:edit, :view] and @show_2fa_options do %>
        <.authenticate_user_form {assigns} />
      <% else %>
        <.webhook_auth_method_form :if={@webhook_auth_method.auth_type} {assigns} />
        <.choose_auth_type_form
          :if={is_nil(@webhook_auth_method.auth_type)}
          {assigns}
        />
      <% end %>
    </div>
    """
  end

  defp authenticate_user_form(assigns) do
    ~H"""
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
      <div class="space-y-4">
        <p class="text-sm">
          You're required to reauthenticate yourself before viewing the webhook
          <%= if @webhook_auth_method.auth_type == :basic do %>
            Password
          <% else %>
            API Key
          <% end %>
        </p>
        <%= if @error_msg do %>
          <div class="alert alert-danger" role="alert">
            {@error_msg}
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
      <.modal_footer class="sm:flex sm:flex-row-reverse gap-3">
        <.button type="submit" theme="primary">
          Done
        </.button>
        <.button
          type="button"
          phx-click="toggle-2fa"
          phx-target={@myself}
          theme="secondary"
        >
          Back
        </.button>
      </.modal_footer>
    </.form>
    """
  end

  defp choose_auth_type_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@changeset}
      phx-change="validate_auth_type"
      phx-submit="choose_auth_type"
      phx-target={@myself}
    >
      <div class="space-y-4">
        <label class="relative block cursor-pointer rounded-lg border bg-white px-[8px] py-2 text-sm shadow-xs">
          <.input
            type="radio"
            id={f[:auth_type].id <> "_basic"}
            field={f[:auth_type]}
            class="sr-only"
            value={:basic}
          />
          <span class="flex items-center gap-x-2.5">
            <.icon name="hero-globe-alt" class="h-10 w-10" />
            Basic HTTP Authentication (username & password)
          </span>
          <span
            class={[
              "pointer-events-none absolute -inset-px rounded-lg",
              if(f[:auth_type].value == :basic,
                do: "outline outline-indigo-600 outline-2 outline-offset-2",
                else: "border-transparent"
              )
            ]}
            aria-hidden="true"
          >
          </span>
        </label>

        <label class="relative block cursor-pointer rounded-lg border bg-white px-[8px] py-2 text-sm shadow-xs focus:outline-none">
          <.input
            type="radio"
            id={f[:auth_type].id <> "_api"}
            field={f[:auth_type]}
            class="sr-only"
            value={:api}
          />
          <span class="flex items-center gap-2">
            <.icon name="hero-code-bracket-square" class="h-10 w-10" />
            API Key Authentication (‘x-api-key’ header)
          </span>
          <span
            class={[
              "pointer-events-none absolute -inset-px rounded-lg",
              if(f[:auth_type].value == :api,
                do: "outline outline-indigo-600 outline-2 outline-offset-2",
                else: "border-transparent"
              )
            ]}
            aria-hidden="true"
          >
          </span>
        </label>
      </div>
      <.modal_footer>
        <.button
          theme="primary"
          type="submit"
          disabled={f[:auth_type].value != :api and f[:auth_type].value != :basic}
        >
          Next
        </.button>
      </.modal_footer>
    </.form>
    """
  end

  defp webhook_auth_method_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@changeset}
      phx-submit="save"
      phx-change="validate"
      phx-target={@myself}
    >
      <.basic_auth_type_form_fields
        :if={@webhook_auth_method.auth_type == :basic}
        form={f}
        {assigns}
      />

      <.api_auth_type_form_fields
        :if={@webhook_auth_method.auth_type == :api}
        form={f}
        {assigns}
      />
      <.modal_footer>
        <%= if @action_buttons != [] do %>
          {render_slot(@action_buttons)}
        <% else %>
          <.button
            type="submit"
            disabled={!@changeset.valid? or @action == :view}
            theme="primary"
          >
            <%= if @action == :new do %>
              Create auth method
            <% else %>
              Save changes
            <% end %>
          </.button>
          <.button type="button" phx-click={@on_close} theme="secondary">
            Cancel
          </.button>
        <% end %>
      </.modal_footer>
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp basic_auth_type_form_fields(assigns) do
    ~H"""
    <.label for={:name}>Auth method name</.label>
    <.input
      type="text"
      field={@form[:name]}
      required="true"
      disabled={@action == :view}
    />

    <div class="hidden sm:block" aria-hidden="true">
      <div class="py-1"></div>
    </div>

    <.label for={:username}>Username</.label>
    <.input
      type="text"
      field={@form[:username]}
      required="true"
      disabled={@action in [:edit, :view]}
    />

    <div class="hidden sm:block" aria-hidden="true">
      <div class="py-1"></div>
    </div>

    <%= if @action in [:edit, :view] do %>
      <div class="mb-3">
        <label class="block text-sm font-semibold leading-6 text-slate-800">
          Password
        </label>
        <.maybe_mask_password_field
          field={@form[:password]}
          sudo_mode?={@sudo_mode?}
          phx_target={@myself}
        />
      </div>
    <% else %>
      <.label for={:password}>Password</.label>
      <.input type="password" field={@form[:password]} required="true" />

      <div class="hidden sm:block" aria-hidden="true">
        <div class="py-1"></div>
      </div>
    <% end %>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp api_auth_type_form_fields(assigns) do
    ~H"""
    <.label for={:name}>Auth method name</.label>
    <.input
      type="text"
      field={@form[:name]}
      required="true"
      disabled={@action == :view}
    />

    <div class="hidden sm:block" aria-hidden="true">
      <div class="py-1"></div>
    </div>

    <.label for={:api_key}>API Key</.label>
    <.maybe_mask_api_key_field
      action={@action}
      field={@form[:api_key]}
      sudo_mode?={@sudo_mode?}
      phx_target={@myself}
    />
    """
  end

  attr :field, :map, required: true
  attr :phx_target, :any, required: true
  attr :sudo_mode?, :boolean, required: true

  defp maybe_mask_password_field(assigns) do
    ~H"""
    <div>
      <div class="mt-2 flex rounded-md shadow-xs">
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
      <div class="mt-2 flex rounded-md shadow-xs">
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
