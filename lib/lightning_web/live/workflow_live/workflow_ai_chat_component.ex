defmodule LightningWeb.WorkflowLive.WorkflowAiChatComponent do
  @moduledoc """
  LiveView component for the persistent workflow AI chat panel.

  This component provides AI assistance for existing workflows, allowing users to
  modify workflows using natural language descriptions while preserving existing
  job code.
  """
  use LightningWeb, :live_component

  alias Phoenix.LiveView.JS

  require Logger

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       workflow_code: nil,
       workflow_params: nil,
       context: nil,
       session_or_message: nil
     )}
  end

  @impl true
  def update(
        %{
          action: :workflow_updated,
          context: context,
          workflow_code: code,
          session_or_message: session_or_message
        },
        socket
      ) do
    {:ok,
     socket
     |> assign(context: context)
     |> assign(session_or_message: session_or_message)
     |> push_event("template_selected", %{template: code})}
  end

  def update(%{action: :sending_ai_message}, socket) do
    notify_parent(:sending_ai_message, %{})
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def handle_event("close-ai-chat", _params, socket) do
    notify_parent(:close_ai_chat, %{})
    {:noreply, socket}
  end

  def handle_event("template-parsed", %{"workflow" => params}, socket) do
    Lightning.Workflows.Comparison.equivalent?(
      socket.assigns.workflow_params,
      params
    )
    |> if do
      {:noreply, socket}
    else
      notify_parent(:workflow_params_changed, %{
        "workflow" => params,
        "opts" => [push_patches: true, context: socket.assigns.context]
      })

      {:noreply, assign(socket, :workflow_params, params)}
    end
  end

  def handle_event(
        "template-parse-error",
        %{
          "error" => error_details,
          "formattedMessage" => formatted_message,
          "template" => _template
        },
        socket
      ) do
    Logger.error(
      "Workflow template parsing failed #{inspect(error_details)} \n\n #{formatted_message}"
    )

    send_update(
      LightningWeb.AiAssistant.Component,
      id: "workflow-ai-assistant-persistent",
      action: :workflow_parse_error,
      error_details: formatted_message,
      session_or_message: socket.assigns.session_or_message
    )

    {:noreply, socket}
  end

  defp notify_parent(action, payload) do
    send(self(), {:workflow_assistant, action, payload})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="TemplateToWorkflow"
      class="absolute inset-y-0 left-0 w-[30%] max-w-[30%] z-20 -translate-x-full"
      phx-mounted={
        JS.remove_class("opacity-0")
        |> JS.transition(
          {"transform transition-transform duration-500 ease-in-out",
           "-translate-x-full", "translate-x-0"},
          time: 500
        )
      }
      phx-remove={
        JS.transition(
          {"transform transition-transform duration-500 ease-in-out",
           "translate-x-0", "-translate-x-full"},
          time: 500
        )
      }
    >
      <div
        id="close-ai-assistant-panel"
        class="absolute top-4 -right-8 z-30 opacity-0"
        phx-mounted={
          JS.transition(
            {"transition-opacity duration-300 ease-in-out delay-300", "opacity-0",
             "opacity-100"},
            time: 300
          )
        }
        phx-hook="Tooltip"
        aria-label="Click to close the AI Assistant panel"
      >
        <button
          type="button"
          phx-click="close-ai-chat"
          phx-target={@myself}
          class="rounded-md text-gray-500 hover:text-gray-700 transition-colors duration-200"
        >
          <span class="sr-only">Close panel</span>
          <.icon name="hero-chevron-double-left" class="h-5 w-5" />
        </button>
      </div>

      <div class="flex h-full flex-col bg-white shadow-xl border-r border-gray-200 overflow-hidden">
        <div class="flex-1 min-h-0">
          <.live_component
            module={LightningWeb.AiAssistant.Component}
            mode={:workflow}
            can_edit_workflow={@can_edit_workflow}
            project={@project}
            current_user={@current_user}
            chat_session_id={@chat_session_id}
            workflow_code={@workflow_code}
            query_params={%{"method" => "ai"}}
            base_url={@base_url}
            action={if(@chat_session_id, do: :show, else: :new)}
            parent_id={@id}
            parent_module={__MODULE__}
            id="workflow-ai-assistant-persistent"
          />
        </div>
      </div>
    </div>
    """
  end
end
