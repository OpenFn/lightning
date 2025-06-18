defmodule LightningWeb.WorkflowLive.WorkflowAiChatComponent do
  @moduledoc """
  LiveView component for the persistent workflow AI chat panel.

  This component provides AI assistance for existing workflows, allowing users to
  modify workflows using natural language descriptions while preserving existing
  job code.
  """
  use LightningWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(chat_session_id: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def handle_event("close_panel", _params, socket) do
    send(self(), {:workflow_ai_chat_event, :close_panel, %{}})
    {:noreply, socket}
  end

  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="w-1/3 bg-white h-full border-r border-gray-200 flex flex-col"
    >
      <div class="flex items-center justify-between p-4 border-b border-gray-200 flex-shrink-0">
        <h3 class="text-lg font-medium text-gray-900">AI Assistant</h3>
        <button
          type="button"
          phx-click="close_panel"
          phx-target={@myself}
          class="text-gray-400 hover:text-gray-600"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>

      <div class="flex-1 min-h-0">
        <.live_component
          module={LightningWeb.AiAssistant.Component}
          mode={:workflow}
          can_edit_workflow={@can_edit_workflow}
          project={@project}
          current_user={@current_user}
          chat_session_id={@chat_session_id}
          query_params={%{}}
          base_url={@base_url}
          action={if(@chat_session_id, do: :show, else: :new)}
          id="workflow-ai-assistant-persistent"
        />
      </div>
    </div>
    """
  end
end
