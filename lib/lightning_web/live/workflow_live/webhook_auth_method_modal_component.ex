defmodule LightningWeb.WorkflowLive.WebhookAuthMethodModalComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Repo
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    {:ok, apply_action(socket, assigns.action, assigns)}
  end

  defp apply_action(
         socket,
         :edit,
         %{project: _, webhook_auth_method: _} = assigns
       ) do
    socket
    |> assign(assigns)
    |> assign(action: :edit)
  end

  defp apply_action(
         socket,
         :new,
         %{project: _, webhook_auth_method: auth_method} = assigns
       ) do
    socket
    |> assign(assigns)
    |> assign(
      action: :new,
      auth_type_changeset: WebhookAuthMethod.changeset(auth_method, %{})
    )
  end

  defp apply_action(
         socket,
         _new_or_index,
         %{project: project, trigger: trigger} = assigns
       ) do
    trigger = Repo.preload(trigger, :webhook_auth_methods)

    project_auth_methods =
      project |> WebhookAuthMethods.list_for_project() |> Repo.preload(:triggers)

    project_selections =
      Enum.into(project_auth_methods, %{}, fn auth_method ->
        {auth_method.id, false}
      end)

    trigger_selections =
      Enum.into(trigger.webhook_auth_methods, %{}, fn auth_method ->
        {auth_method.id, true}
      end)

    selections = Map.merge(project_selections, trigger_selections)

    auth_method = %WebhookAuthMethod{project_id: project.id}

    socket
    |> assign(assigns)
    |> assign(
      action: if(project_auth_methods == [], do: :new, else: :index),
      trigger: trigger,
      selections: selections,
      webhook_auth_method: auth_method,
      auth_type_changeset: WebhookAuthMethod.changeset(auth_method, %{}),
      project_auth_methods: project_auth_methods
    )
  end

  @impl true
  def handle_event(
        "validate_auth_type",
        %{"webhook_auth_method" => params},
        socket
      ) do
    changeset =
      socket.assigns.webhook_auth_method
      |> WebhookAuthMethod.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :auth_type_changeset, changeset)}
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

  def handle_event(
        "toggle_selection",
        %{"auth_method_id" => id},
        %{assigns: assigns} = socket
      ) do
    selections = Map.update(assigns.selections, id, false, fn val -> !val end)
    {:noreply, assign(socket, selections: selections)}
  end

  def handle_event(
        "new_auth_method",
        _params,
        %{assigns: %{project: project}} = socket
      ) do
    auth_method = %WebhookAuthMethod{project_id: project.id}

    {:noreply,
     assign(socket,
       webhook_auth_method: auth_method,
       auth_type_changeset: WebhookAuthMethod.changeset(auth_method, %{}),
       action: :new
     )}
  end

  def handle_event(
        "edit_auth_method",
        %{"id" => id},
        %{assigns: assigns} = socket
      ) do
    auth_method =
      Enum.find(assigns.project_auth_methods, fn auth_method ->
        auth_method.id == id
      end)

    {:noreply,
     apply_action(socket, :edit, %{
       webhook_auth_method: auth_method,
       project: assigns.project
     })}
  end

  def handle_event(
        "save",
        _params,
        %{assigns: %{action: :index} = assigns} = socket
      ) do
    selected_auth_method_ids =
      assigns.selections
      |> Enum.filter(fn {_key, value} -> value end)
      |> Enum.map(fn {key, _value} -> key end)

    auth_methods =
      Enum.filter(assigns.project_auth_methods, fn auth_method ->
        auth_method.id in selected_auth_method_ids
      end)

    {:ok, _trigger} =
      WebhookAuthMethods.update_trigger_auth_methods(
        assigns.trigger,
        auth_methods
      )

    {:noreply,
     socket
     |> put_flash(:info, "Trigger webhook credentials updated successfully")
     |> push_navigate(to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal
        id={@id}
        phx-fragment-match={show_modal(@id)}
        phx-hook="FragmentMatch"
        width={if(@action in [:new, :edit], do: "min-w-1/3 max-w-xl", else: "")}
      >
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              <%= case @action do %>
                <% :new -> %>
                  <%= case @webhook_auth_method.auth_type do %>
                    <% nil -> %>
                      Add an authentication method
                    <% :basic -> %>
                      Create a Basic HTTP Credential
                    <% :api -> %>
                      Create an API Credential
                  <% end %>
                <% :edit -> %>
                  Edit webhook credential
                <% :index -> %>
                  Webhook Authentication Credentials
              <% end %>
            </span>

            <button
              phx-click={JS.navigate(@return_to)}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <:subtitle>
          <%= if @action == :new && @webhook_auth_method.auth_type do %>
            <span class="italic text-xs">
              Webhook authentication credentials are accessible to everyone within your project and can be managed via
              <span class="text-primary-700 underline">your settings here.</span>
            </span>
          <% end %>
        </:subtitle>

        <%= case assigns do %>
          <% %{action: :index} -> %>
            <.auth_methods_table {assigns} />
          <% %{action: :new, webhook_auth_method: %{auth_type: nil}} -> %>
            <.choose_auth_type_form {assigns} />
          <% _other -> %>
            <.live_component
              module={LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent}
              id={@webhook_auth_method.id || "new_webhook_auth_method"}
              action={@action}
              trigger={@trigger}
              return_to={@return_to}
              webhook_auth_method={@webhook_auth_method}
            />
        <% end %>
      </.modal>
    </div>
    """
  end

  defp auth_methods_table(assigns) do
    ~H"""
    <LightningWeb.WorkflowLive.Components.webhook_auth_methods_table
      auth_methods={@project_auth_methods}
      on_row_select={
        fn auth_method ->
          JS.push("toggle_selection",
            value: %{auth_method_id: auth_method.id},
            target: @myself
          )
        end
      }
      row_selected?={fn auth_method -> @selections[auth_method.id] end}
    >
      <:action :let={auth_method}>
        <a
          id={"edit_auth_method_link_#{auth_method.id}"}
          href="#"
          class="text-indigo-600 hover:text-indigo-900"
          phx-click="edit_auth_method"
          phx-value-id={auth_method.id}
          phx-target={@myself}
        >
          Edit<span class="sr-only">, <%= auth_method.name %></span>
        </a>
      </:action>
    </LightningWeb.WorkflowLive.Components.webhook_auth_methods_table>
    <div class="mt-4 flex justify-between content-center ">
      <div class="flex flex-wrap items-center">
        <.link
          href="#"
          class="inline-flex content-center text-primary-700 underline text-md font-semibold"
          phx-click="new_auth_method"
          phx-target={@myself}
        >
          Create a new webhook credential
        </.link>
      </div>
      <div class="sm:flex sm:flex-row-reverse">
        <button
          id="update_trigger_auth_methods_button"
          type="button"
          phx-click="save"
          phx-target={@myself}
          class="inline-flex w-full justify-center rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
        >
          Save
        </button>
        <button
          type="button"
          phx-click={JS.navigate(@return_to)}
          class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  defp choose_auth_type_form(assigns) do
    ~H"""
    <.form
      :let={f}
      id={"choose_auth_type_form_#{@id}"}
      for={@auth_type_changeset}
      phx-change="validate_auth_type"
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
          <%= Phoenix.HTML.Form.radio_button(f, :auth_type, :basic, class: "sr-only") %>
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
          <%= Phoenix.HTML.Form.radio_button(f, :auth_type, :api, class: "sr-only") %>
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
    """
  end
end
