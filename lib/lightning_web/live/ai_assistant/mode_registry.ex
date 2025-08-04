defmodule LightningWeb.Live.AiAssistant.ModeRegistry do
  @moduledoc """
  Registry for AI Assistant interaction modes.

  Manages mode discovery, metadata retrieval, and feature detection.
  """

  alias LightningWeb.Live.AiAssistant.Modes.JobCode
  alias LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate

  @type mode_id :: atom()
  @type mode_module :: module()
  @type mode_metadata :: %{
          optional(:features) => [String.t()],
          optional(:category) => String.t(),
          id: mode_id(),
          name: String.t(),
          description: String.t(),
          icon: String.t(),
          chat_param: String.t()
        }

  @doc """
  Returns all registered modes.
  """
  @spec register_modes() :: %{mode_id() => mode_module()}
  def register_modes do
    Lightning.Config.ai_assistant_modes() ||
      %{
        job: JobCode,
        workflow: WorkflowTemplate
      }
  end

  @doc """
  Gets the handler module for a mode.
  """
  @spec get_handler(mode_id()) :: mode_module()
  def get_handler(mode) do
    Map.get(register_modes(), mode, JobCode)
  end

  @doc """
  Lists all available modes with metadata.
  """
  @spec available_modes() :: [mode_metadata()]
  def available_modes do
    register_modes()
    |> Enum.map(fn {id, module} ->
      Map.put(module.metadata(), :id, id)
    end)
  end

  @doc """
  Gets metadata for a specific mode.
  """
  @spec get_mode_metadata(mode_id()) :: mode_metadata()
  def get_mode_metadata(mode) do
    handler = get_handler(mode)
    Map.put(handler.metadata(), :id, mode)
  end

  @doc """
  Returns the default mode.
  """
  @spec default_mode() :: mode_id()
  def default_mode, do: :job

  @doc """
  Checks if a mode exists.
  """
  @spec mode_exists?(mode_id()) :: boolean()
  def mode_exists?(mode) do
    Map.has_key?(register_modes(), mode)
  end

  @doc """
  Gets the chat parameter name for a mode.
  """
  @spec get_chat_param(mode_id()) :: String.t()
  def get_chat_param(mode) do
    get_mode_metadata(mode)[:chat_param] || "chat"
  end

  @doc """
  Creates a callbacks map for parent component communication.

  ## Example

      create_callbacks(%{
        on_workflow_update: &handle_workflow_update/2,
        on_session_change: &handle_session_change/1
      })

  """
  @spec create_callbacks(map()) :: map()
  def create_callbacks(opts \\ %{}) do
    %{
      on_workflow_update: opts[:on_workflow_update] || fn _, _ -> :ok end,
      on_workflow_clear: opts[:on_workflow_clear] || fn -> :ok end,
      on_workflow_message_send:
        opts[:on_workflow_message_send] || fn _ -> :ok end,
      on_session_change: opts[:on_session_change] || fn _ -> :ok end
    }
  end

  @doc """
  Lists modes supporting a specific feature.
  """
  @spec modes_with_feature(String.t()) :: [mode_id()]
  def modes_with_feature(feature) do
    register_modes()
    |> Enum.filter(fn {_id, module} ->
      metadata = module.metadata()
      features = Map.get(metadata, :features, [])
      feature in features
    end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Gets all unique features across all modes.
  """
  @spec all_features() :: [String.t()]
  def all_features do
    register_modes()
    |> Enum.flat_map(fn {_id, module} ->
      metadata = module.metadata()
      Map.get(metadata, :features, [])
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
