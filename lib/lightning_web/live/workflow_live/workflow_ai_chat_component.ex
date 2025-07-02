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
    {:ok, assign(socket, workflow_code: nil)}
  end

  @impl true
  def update(%{action: :workflow_updated, workflow_code: code}, socket) do
    IO.inspect(code, label: "Updating workflow code in AI chat component")

    {:ok,
     assign(socket, workflow_code: code)
     |> push_event("template_selected", %{template: code})}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("template-parsed", %{"workflow" => params}, socket) do
    IO.inspect(params, label: "Template selected in AI chat component")

    notify_parent(:form_changed, %{
      "workflow" => params,
      "opts" => [push_patches: false]
    })

    {:noreply, socket}
  end

  defp notify_parent(action, payload) do
    send(self(), {:workflow_component_event, action, payload})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="TemplateToWorkflow"
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
    """
  end
end
