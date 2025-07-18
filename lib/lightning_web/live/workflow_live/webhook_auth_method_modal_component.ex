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
  def update(assigns, socket) do
    {:ok, apply_action(socket, assigns.action, assigns)}
  end

  defp apply_action(
         socket,
         :edit,
         %{project: _, webhook_auth_method: _, current_user: _} = assigns
       ) do
    socket
    |> assign(assigns)
    |> assign(is_form_valid: false)
    |> assign(action: :edit)
  end

  defp apply_action(
         socket,
         :new,
         %{project: _, current_user: _, webhook_auth_method: auth_method} =
           assigns
       ) do
    socket
    |> assign(assigns)
    |> assign(
      action: :new,
      is_form_valid: false,
      auth_type_changeset:
        WebhookAuthMethod.changeset(auth_method, %{auth_type: :basic})
    )
  end

  defp apply_action(
         socket,
         :display_triggers,
         %{project: _, webhook_auth_method: _, current_user: _} = assigns
       ) do
    socket
    |> assign(assigns)
    |> assign(is_form_valid: false)
    |> assign(action: :display_triggers)
  end

  defp apply_action(
         socket,
         :delete,
         assigns
       ) do
    socket
    |> assign(assigns)
    |> assign(is_form_valid: false)
    |> assign(action: :delete)
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

  def handle_info({:form_validity, is_valid}, socket) do
    {:noreply, assign(socket, is_form_valid: is_valid)}
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

  def handle_event("validate_auth_type", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "choose_auth_type",
        %{"webhook_auth_method" => params},
        socket
      ) do
    auth_method =
      WebhookAuthMethods.create_changeset(
        socket.assigns.webhook_auth_method,
        params
      )

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
       auth_type_changeset:
         WebhookAuthMethod.changeset(auth_method, %{auth_type: :basic}),
       action: :new
     )}
  end

  def handle_event(
        "display_triggers",
        %{"id" => id},
        %{assigns: assigns} = socket
      ) do
    auth_method =
      Enum.find(assigns.project_auth_methods, fn auth_method ->
        auth_method.id == id
      end)

    {:noreply,
     apply_action(socket, :display_triggers, %{
       webhook_auth_method: auth_method,
       current_user: assigns.current_user,
       project: assigns.project
     })}
  end

  def handle_event("close_webhook_modal", _, socket) do
    %{
      action: action,
      return_to: return_to,
      project_auth_methods: auth_methods,
      project: project
    } =
      socket.assigns

    current_page = return_to |> String.split("/") |> List.last()

    if current_page == "settings#webhook_security" do
      {:noreply,
       socket
       |> push_navigate(to: socket.assigns.return_to)}
    else
      case {action, auth_methods} do
        {:index, _} ->
          {:noreply, push_patch(socket, to: return_to)}

        {:new, []} ->
          {:noreply,
           socket |> assign(action: :new) |> assign_new_auth_method_form(project)}

        _ ->
          {:noreply, socket |> assign(action: :index)}
      end
    end
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

    {:ok, _trigger} =
      WebhookAuthMethods.update_trigger_auth_methods(
        assigns.trigger,
        auth_methods,
        actor: assigns.current_user
      )

    {:noreply,
     socket
     |> put_flash(:info, "Trigger webhook auth methods updated successfully")
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
                      Create a "basic auth" method
                    <% :api -> %>
                      Create an "API token" method
                  <% end %>
                <% :edit -> %>
                  Webhook Authentication Method
                <% :display_triggers -> %>
                  Associated Workflow Triggers
                <% :delete -> %>
                  Delete Authentication Method
                <% :index -> %>
                  Webhook Authentication Methods
              <% end %>
            </span>

            <button
              phx-click={
                hide_modal(@id)
                |> JS.push("close_webhook_modal")
              }
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <:subtitle>
          <%= if @action == :new && @webhook_auth_method.auth_type do %>
            <span class="italic text-xs">
              Webhook authentication methods are accessible to everyone within your project and can be managed via
              <.link
                id="access-settings"
                navigate={
                  ~p"/projects/#{assigns.webhook_auth_method.project_id}/settings#webhook_security"
                }
                class="link flex-1 rounded-md"
                role="button"
                target="_blank"
              >
                your settings here.
              </.link>
            </span>
          <% end %>
        </:subtitle>

        <%= case assigns do %>
          <% %{action: :index} -> %>
            <.auth_methods_table {assigns} />
          <% %{action: :new, webhook_auth_method: %{auth_type: nil}} -> %>
            <.choose_auth_type_form {assigns} />
          <% %{action: :display_triggers} -> %>
            <.linked_triggers_list {assigns} />
          <% other -> %>
            <.live_component
              module={LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent}
              id={
                Enum.join(
                  [other.id, @webhook_auth_method.id || "new_webhook_auth_method"],
                  "_"
                )
              }
              action={@action}
              trigger={@trigger}
              return_to={@return_to}
              current_user={@current_user}
              webhook_auth_method={@webhook_auth_method}
            />
        <% end %>
      </.modal>
    </div>
    """
  end

  defp assign_new_auth_method_form(socket, project) do
    auth_method = %WebhookAuthMethod{project_id: project.id}

    assign(socket,
      webhook_auth_method: auth_method,
      auth_type_changeset: WebhookAuthMethod.changeset(auth_method, %{}),
      is_form_valid: false
    )
  end

  defp linked_triggers_list(assigns) do
    assigns =
      assign(assigns,
        webhook_auth_method:
          Lightning.Repo.preload(assigns.webhook_auth_method,
            triggers: [:workflow]
          )
      )

    ~H"""
    <div class="space-y-4 ml-[24px] mr-[24px]">
      <p class="mb-4">
        You have {length(assigns.webhook_auth_method.triggers)}
        <span class="font-semibold">Workflows</span>
        associated with the "<span class="font-semibold">My Auth</span>" authentication method:
      </p>
      <ul class="list-disc pl-5 mb-4">
        <%= for trigger <- assigns.webhook_auth_method.triggers do %>
          <li class="mb-2">
            <.link
              navigate={
                ~p"/projects/#{assigns.webhook_auth_method.project_id}/w/#{trigger.workflow.id}?s=#{trigger.id}"
              }
              class="link flex-1 rounded-md"
              role="button"
              target="_blank"
            >
              {trigger.workflow.name}
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
    <.modal_footer class="mt-6 mx-6">
      <div class="sm:flex sm:flex-row-reverse">
        <.button
          type="button"
          phx-click="close_webhook_modal"
          phx-target={@myself}
          theme="primary"
        >
          Close
        </.button>
      </div>
    </.modal_footer>
    """
  end

  defp auth_methods_table(assigns) do
    ~H"""
    <div class="my-4 mx-px">
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
            <a
              :if={auth_method.triggers != []}
              id={"display_linked_triggers_link_#{auth_method.id}"}
              href="#"
              class="text-indigo-600 hover:text-indigo-900"
              phx-click="display_triggers"
              phx-value-id={auth_method.id}
              phx-target={@myself}
            >
              {Enum.count(auth_method.triggers)}
            </a>
            <span
              :if={auth_method.triggers == []}
              class="italic font-normal text-gray-300"
            >
              No associated triggers...
            </span>

            <div class="text-left">
              <.live_component
                module={LightningWeb.WorkflowLive.WebhookAuthMethodModalComponent}
                id={"display_linked_triggers_#{auth_method.id}_modal"}
                action={:display_triggers}
                project={auth_method.project}
                webhook_auth_method={auth_method}
                current_user={@current_user}
                return_to={@return_to}
                trigger={nil}
              />
            </div>
          </span>
        </:linked_triggers>
        <:action :let={auth_method}>
          <a
            id={"edit_auth_method_link_#{auth_method.id}"}
            href="#"
            class="text-indigo-600 hover:text-indigo-900"
            phx-click="edit_auth_method"
            phx-value-id={auth_method.id}
            phx-target={@myself}
          >
            View<span class="sr-only">, <%= auth_method.name %></span>
          </a>
        </:action>
      </LightningWeb.WorkflowLive.Components.webhook_auth_methods_table>
    </div>
    <.modal_footer class="mt-6 mx-6">
      <div class="flex justify-between content-center ">
        <div class="flex flex-wrap items-center">
          <.link
            href="#"
            class="link inline-flex content-center text-md font-semibold"
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
          <.button
            type="button"
            phx-click={
              hide_modal(@id)
              |> JS.push("close_webhook_modal")
            }
            phx-target={@myself}
            theme="secondary"
          >
            Cancel
          </.button>
        </div>
      </div>
    </.modal_footer>
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
      <div class="space-y-4 ml-[24px] mr-[24px]">
        <label class="relative block cursor-pointer rounded-lg border bg-white px-[8px] py-2 text-sm shadow-xs">
          <.input
            type="radio"
            id={f[:auth_type].id <> "_basic"}
            field={f[:auth_type]}
            class="sr-only"
            value={:basic}
          />
          <span class="flex items-center gap-x-2.5">
            <Heroicons.globe_alt class="h-10 w-10" />
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
            <Heroicons.code_bracket_square class="h-10 w-10" />
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
      <.modal_footer class="mx-6 mt-6">
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
end
