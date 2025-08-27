defmodule LightningWeb.WorkflowLive.WebhookAuthMethodModalComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Repo
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok, assign(socket, project_auth_methods: [])}
  end

  @impl true
  def update(%{on_close: _, on_save: _} = assigns, socket) do
    {:ok, apply_action(socket, assigns.action, assigns)}
  end

  defp apply_action(
         socket,
         :view,
         %{project: _, webhook_auth_method: _, current_user: _} = assigns
       ) do
    socket
    |> assign(assigns)
    |> assign(action: :view)
  end

  defp apply_action(
         socket,
         _new_or_index,
         %{project: project, trigger: trigger, current_user: _} = assigns
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

    socket
    |> assign(assigns)
    |> assign(
      action: if(project_auth_methods == [], do: :new, else: :index),
      trigger: trigger,
      selections: selections,
      project_auth_methods: project_auth_methods
    )
    |> assign_new_auth_method_form(project)
  end

  @impl true
  def handle_event(
        "toggle_selection",
        %{"auth_method_id" => id},
        %{assigns: assigns} = socket
      ) do
    selections = Map.update(assigns.selections, id, false, fn val -> !val end)
    {:noreply, assign(socket, selections: selections)}
  end

  def handle_event("toggle_action", %{"action" => action}, socket) do
    action_assigns =
      Map.take(socket.assigns, [
        :project,
        :webhook_auth_method,
        :trigger,
        :current_user
      ])

    socket
    |> apply_action(String.to_existing_atom(action), action_assigns)
    |> noreply()
  end

  def handle_event("new_auth_method", _params, socket) do
    socket
    |> assign(action: :new)
    |> assign_new_auth_method_form(socket.assigns.project)
    |> noreply()
  end

  def handle_event(
        "view_auth_method",
        %{"id" => id},
        %{assigns: assigns} = socket
      ) do
    auth_method =
      Enum.find(assigns.project_auth_methods, fn auth_method ->
        auth_method.id == id
      end)

    {:noreply,
     apply_action(socket, :view, %{
       webhook_auth_method: auth_method,
       current_user: assigns.current_user,
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

    {:ok, trigger} =
      WebhookAuthMethods.update_trigger_auth_methods(
        assigns.trigger,
        auth_methods,
        actor: assigns.current_user
      )

    if socket.assigns.on_save do
      socket.assigns.on_save.(trigger)
    end

    {:noreply,
     socket
     |> put_flash(:info, "Trigger webhook auth methods updated successfully")
     |> push_patch(to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal
        id={"#{@id}_modal"}
        show={true}
        width={if(@action in [:new, :view], do: "min-w-1/3 max-w-xl", else: "")}
      >
        <.auth_methods_index :if={@action == :index} {assigns} />

        <.live_component
          :if={@action == :new}
          module={LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent}
          id="new_webhook_auth_method"
          action={@action}
          trigger={@trigger}
          return_to={@return_to}
          on_close={@on_close}
          on_save={@on_save}
          current_user={@current_user}
          webhook_auth_method={@webhook_auth_method}
        >
          <:subtitle>
            <.manage_auth_methods_subtitle project_id={@project.id} />
          </:subtitle>
        </.live_component>

        <.live_component
          :if={@action == :view}
          module={LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent}
          id={"view_webhook_auth_method_#{@webhook_auth_method.id}"}
          action={@action}
          return_to={@return_to}
          on_close={@on_close}
          current_user={@current_user}
          webhook_auth_method={@webhook_auth_method}
        >
          <:subtitle>
            <.manage_auth_methods_subtitle project_id={@project.id} />
          </:subtitle>
          <:action_buttons>
            <.button
              type="button"
              theme="secondary"
              phx-click="toggle_action"
              phx-value-action="index"
              phx-target={@myself}
            >
              Back
            </.button>
          </:action_buttons>
        </.live_component>
      </.modal>
    </div>
    """
  end

  defp assign_new_auth_method_form(socket, project) do
    auth_method = %WebhookAuthMethod{project_id: project.id}

    assign(socket, webhook_auth_method: auth_method)
  end

  attr :project_id, :string, required: true

  defp manage_auth_methods_subtitle(assigns) do
    ~H"""
    <span class="italic text-xs">
      Webhook authentication methods are accessible to everyone within your project and can be managed via
      <.link
        id="access-settings"
        navigate={~p"/projects/#{@project_id}/settings#webhook_security"}
        class="link"
        target="_blank"
      >
        your settings here.
      </.link>
    </span>
    """
  end

  defp auth_methods_index(assigns) do
    ~H"""
    <.modal_title>
      <div class="flex justify-between">
        <span>
          Webhook Authentication Methods
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
        <.manage_auth_methods_subtitle project_id={@project.id} />
      </:subtitle>
    </.modal_title>
    <div class="my-[16px]"></div>
    <LightningWeb.WorkflowLive.Components.webhook_auth_methods_table
      auth_methods={@project_auth_methods}
      current_user={@current_user}
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
      <:linked_triggers :let={auth_method}>
        <span class="relative font-normal">
          <span :if={auth_method.triggers != []}>
            {Enum.count(auth_method.triggers)}
          </span>
          <span
            :if={auth_method.triggers == []}
            class="italic font-normal text-gray-300"
          >
            No associated triggers...
          </span>
        </span>
      </:linked_triggers>
      <:action :let={auth_method}>
        <a
          id={"view_auth_method_link_#{auth_method.id}"}
          href="#"
          class="text-indigo-600 hover:text-indigo-900"
          phx-click="view_auth_method"
          phx-value-id={auth_method.id}
          phx-target={@myself}
        >
          View<span class="sr-only">, <%= auth_method.name %></span>
        </a>
      </:action>
    </LightningWeb.WorkflowLive.Components.webhook_auth_methods_table>
    <.modal_footer class="flex justify-between content-center">
      <div class="flex flex-wrap items-center">
        <.link
          href="#"
          class="link inline-flex content-center text-sm font-semibold"
          phx-click="new_auth_method"
          phx-target={@myself}
        >
          Create a new webhook auth method
        </.link>
      </div>
      <div class="sm:flex sm:flex-row-reverse gap-3">
        <.button
          id="update_trigger_auth_methods_button"
          type="button"
          theme="primary"
          phx-click="save"
          phx-target={@myself}
        >
          Save
        </.button>
        <.button type="button" phx-click={@on_close} theme="secondary">
          Cancel
        </.button>
      </div>
    </.modal_footer>
    """
  end
end
