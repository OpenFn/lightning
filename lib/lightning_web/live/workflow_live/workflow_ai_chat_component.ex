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
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="w-1/3 bg-white h-full border-r border-gray-200 flex flex-col"
    >
      <div class="flex-1 min-h-0">
        <.live_component
          module={LightningWeb.AiAssistant.Component}
          mode={:workflow}
          can_edit_workflow={@can_edit_workflow}
          project={@project}
          current_user={@current_user}
          chat_session_id={@chat_session_id}
          workflow_params={@workflow_params}
          #
          Pass
          this
          directly
          query_params={%{"method" => "ai"}}
          base_url={@base_url}
          action={if(@chat_session_id, do: :show, else: :new)}
          id="workflow-ai-assistant-persistent"
        />
      </div>
    </div>
    """
  end
end
