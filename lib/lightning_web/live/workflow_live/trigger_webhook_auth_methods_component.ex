defmodule LightningWeb.WorkflowLive.TriggerWebhookAuthMethodsComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Repo
  alias Lightning.WebhookAuthMethods
  alias Phoenix.LiveView.JS

  @impl true
  def update(%{project: project, trigger: trigger} = assigns, socket) do
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

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       trigger: trigger,
       selections: selections,
       project_auth_methods: project_auth_methods
     )}
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

  def handle_event(
        "save",
        _params,
        %{assigns: assigns} = socket
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
     |> put_flash(:info, "Webhook credentials updated successfully")
     |> push_navigate(to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id}>
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              Webhook Authentication Credentials
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
              href="#"
              class="text-indigo-600 hover:text-indigo-900"
              phx-click={show_modal("webhook_edit_modal_#{auth_method.id}")}
            >
              Edit<span class="sr-only">, <%= auth_method.name %></span>
            </a>
            <div class="whitespace-normal text-left">
              <.live_component
                module={LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent}
                id={"webhook_edit_modal_#{auth_method.id}"}
                action={:edit}
                return_to={@return_to}
                webhook_auth_method={auth_method}
              />
            </div>
          </:action>
        </LightningWeb.WorkflowLive.Components.webhook_auth_methods_table>
        <div class="mt-4 flex justify-between content-center ">
          <div class="flex flex-wrap items-center">
            <.link
              href="#"
              class="inline-flex content-center text-primary-700 underline text-md font-semibold"
              phx-click={show_modal("new_trigger_webhook_auth_method_modal")}
            >
              Create a new webhook credential
            </.link>

            <.live_component
              module={LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent}
              id="new_trigger_webhook_auth_method_modal"
              action={:new}
              trigger={@trigger}
              return_to={
                ~p"/projects/#{@project.id}/w/#{@trigger.workflow_id}?#{%{s: @trigger.id}}"
              }
              webhook_auth_method={
                %Lightning.Workflows.WebhookAuthMethod{project_id: @project.id}
              }
            />
          </div>
          <div class="sm:flex sm:flex-row-reverse">
            <button
              type="button"
              phx-click="save"
              phx-target={@myself}
              class="inline-flex w-full justify-center rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
            >
              Save
            </button>
            <button
              type="button"
              phx-click={hide_modal(@id)}
              class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
            >
              Cancel
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end
end
