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
end
