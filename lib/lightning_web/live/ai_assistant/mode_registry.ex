defmodule LightningWeb.Live.AiAssistant.ModeRegistry do
  @moduledoc """
  Registry for managing available AI Assistant modes.

  This module maintains a registry of all available AI Assistant modes and provides
  functions to access and manage them. Each mode is implemented as a module that
  follows the `ModeBehavior` protocol.

  ## Available Modes
  * `:job` - Handles job code assistance through the `JobCode` module
  * `:workflow` - Handles workflow template generation through the `WorkflowTemplate` module
  """

  alias LightningWeb.Live.AiAssistant.Modes.JobCode
  alias LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate

  @doc """
  Returns a map of all registered modes.

  The map keys are mode identifiers (atoms) and the values are the corresponding
  handler modules that implement the `ModeBehavior` protocol.

  ## Returns
    * `%{mode_id => handler_module}` - A map of mode identifiers to their handler modules

  ## Example
      iex> register_modes()
      %{
        job: LightningWeb.Live.AiAssistant.Modes.JobCode,
        workflow: LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate
      }
  """
  def register_modes do
    Application.get_env(:lightning, :ai_assistant_modes, %{
      job: JobCode,
      workflow: WorkflowTemplate
    })
  end

  @doc """
  Gets the handler module for a given mode.

  If the requested mode is not found in the registry, returns the default `JobCode`
  handler as a fallback.

  ## Parameters
    * mode - The mode identifier (atom) to look up

  ## Returns
    * `handler_module` - The module that implements the `ModeBehavior` protocol for the requested mode

  ## Example
      iex> get_handler(:job)
      LightningWeb.Live.AiAssistant.Modes.JobCode

      iex> get_handler(:unknown)
      LightningWeb.Live.AiAssistant.Modes.JobCode
  """
  def get_handler(mode) do
    Map.get(register_modes(), mode, JobCode)
  end

  @doc """
  Returns a list of all available modes with their metadata.

  Each mode in the list includes its identifier and any additional metadata
  provided by the handler module's `metadata/0` function.

  ## Returns
    * `[%{id: mode_id, ...metadata}]` - A list of maps containing mode identifiers and their metadata

  ## Example
      iex> available_modes()
      [
        %{id: :job, name: "Job Code Assistant", description: "Get help with job code", icon: "hero-cpu-chip"},
        %{id: :workflow, name: "Workflow Builder", description: "Generate workflow templates", icon: "hero-cpu-chip"}
      ]
  """
  def available_modes do
    register_modes()
    |> Enum.map(fn {id, module} ->
      Map.put(module.metadata(), :id, id)
    end)
  end

  @doc """
  Gets metadata for a specific mode.

  ## Parameters
    * mode - The mode identifier (atom) to look up

  ## Returns
    * `map()` - The metadata for the mode, or default metadata if not found

  ## Example
      iex> get_mode_metadata(:job)
      %{id: :job, name: "Job Code Assistant", description: "Get help with job code", icon: "hero-cpu-chip"}
  """
  def get_mode_metadata(mode) do
    handler = get_handler(mode)
    Map.put(handler.metadata(), :id, mode)
  end

  @doc """
  Checks if a mode supports template generation.

  ## Parameters
    * mode - The mode identifier (atom) to check

  ## Returns
    * `boolean()` - Whether the mode supports template generation

  ## Example
      iex> supports_template_generation?(:workflow)
      true

      iex> supports_template_generation?(:job)
      false
  """
  def supports_template_generation?(mode) do
    get_handler(mode).supports_template_generation?()
  end
end
