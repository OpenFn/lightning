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
       session_or_message: nil
     )}
  end

  @impl true
  def update(
        %{
          action: :workflow_updated,
          workflow_code: code,
          session_or_message: session_or_message
        },
        socket
      ) do
    {:ok,
     socket
     |> assign(session_or_message: session_or_message)
     |> push_event("template_selected", %{template: code})}
  end

  def update(%{action: :sending_ai_message}, socket) do
    {:ok, push_event(socket, "set-disabled", %{disabled: true})}
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
    if Lightning.Workflows.Comparison.equivalent?(
         socket.assigns.workflow_params,
         params
       ) do
      {:noreply, socket}
    else
      changeset =
        Lightning.Workflows.Workflow.changeset(socket.assigns.workflow, params)

      if changeset.valid? do
        notify_parent(:workflow_params_changed, %{"workflow" => params})

        {:noreply, assign(socket, :workflow_params, params)}
      else
        error_details = format_changeset_errors(changeset)

        Logger.error(
          "Workflow changeset validation failed: #{inspect(error_details)}"
        )

        send_update(
          LightningWeb.AiAssistant.Component,
          id: "workflow-ai-assistant-persistent",
          action: :workflow_parse_error,
          error_details: error_details,
          session_or_message: socket.assigns.session_or_message
        )

        {:noreply, socket}
      end
    end
  end

  def handle_event(
        "template-parse-error",
        %{
          "error" => error_details,
          "formattedMessage" => formatted_message,
          "template" => template
        },
        socket
      ) do
    Logger.error(template)

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
            workflow={@workflow}
            current_user={@current_user}
            chat_session_id={@chat_session_id}
            workflow_code={@workflow_code |> dbg}
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

  defp notify_parent(action, payload) do
    send(self(), {:workflow_assistant, action, payload})
  end

  defp format_changeset_errors(changeset) do
    errors = traverse_changeset_errors(changeset)

    Enum.map_join(errors, "\n", fn {path, field, message} ->
      "#{Enum.join(path ++ [field], ".")} - #{message}"
    end)
  end

  defp traverse_changeset_errors(changeset, path \\ []) do
    current_errors =
      changeset.errors
      |> Enum.map(fn {field, {message, _opts}} ->
        {path, field, message}
      end)

    nested_errors =
      [:jobs, :edges, :triggers]
      |> Enum.flat_map(fn assoc ->
        case Map.get(changeset.changes, assoc) do
          nil ->
            []

          changesets when is_list(changesets) ->
            process_changeset_list(changesets, path, assoc)

          %Ecto.Changeset{} = cs ->
            traverse_changeset_errors(cs, path ++ [assoc])

          _ ->
            []
        end
      end)

    current_errors ++ nested_errors
  end

  defp process_changeset_list(changesets, path, assoc) do
    changesets
    |> Enum.with_index()
    |> Enum.flat_map(fn {cs, index} ->
      case cs do
        %Ecto.Changeset{} ->
          identifier = get_changeset_identifier(cs)
          new_path = path ++ [assoc, identifier || index]
          traverse_changeset_errors(cs, new_path)

        _ ->
          []
      end
    end)
  end

  defp get_changeset_identifier(changeset) do
    data = changeset.data

    cond do
      Map.has_key?(data, :name) ->
        get_name_identifier(changeset, data)

      Map.has_key?(data, :source_job_id) ||
          Map.has_key?(data, :source_trigger_id) ->
        get_edge_identifier(changeset, data)

      true ->
        get_id_identifier(changeset, data)
    end
  end

  defp get_name_identifier(changeset, data) do
    case get_in(changeset.changes, [:name]) || Map.get(data, :name) do
      nil -> nil
      name -> "\"#{name}\""
    end
  end

  defp get_edge_identifier(changeset, data) do
    source = get_edge_source(changeset, data)
    target = get_edge_target(changeset, data)
    "#{source}→#{target}"
  end

  defp get_edge_source(changeset, data) do
    cond do
      source_job_id =
          get_in(changeset.changes, [:source_job_id]) ||
            Map.get(data, :source_job_id) ->
        "job:#{shorten_id(source_job_id)}"

      source_trigger_id =
          get_in(changeset.changes, [:source_trigger_id]) ||
            Map.get(data, :source_trigger_id) ->
        "trigger:#{shorten_id(source_trigger_id)}"

      true ->
        "unknown"
    end
  end

  defp get_edge_target(changeset, data) do
    target =
      get_in(changeset.changes, [:target_job_id]) ||
        Map.get(data, :target_job_id)

    if target, do: "job:#{shorten_id(target)}", else: "unknown"
  end

  defp get_id_identifier(changeset, data) do
    case get_in(changeset.changes, [:id]) || Map.get(data, :id) do
      nil -> nil
      id -> "id:#{shorten_id(id)}"
    end
  end

  defp shorten_id(id) when is_binary(id) do
    id
  end

  defp shorten_id(_), do: "unknown"
end
