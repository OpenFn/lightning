defmodule LightningWeb.Live.AiAssistant.ModeRegistry do
  @moduledoc """
  Centralized registry for managing AI Assistant interaction modes.

  This module provides a pluggable architecture for AI Assistant modes, enabling
  dynamic mode discovery, configuration, and management. It serves as the central
  coordination point for all AI assistance capabilities within Lightning.
  """

  alias LightningWeb.Live.AiAssistant.Modes.JobCode

  @doc """
  Returns the complete registry of available AI Assistant modes.

  Retrieves mode mappings from application configuration, providing the
  foundation for all mode-related operations. The registry can be customized
  through application configuration to enable/disable modes or add custom implementations.

  ## Configuration

  Modes are configured in application config:
  ```elixir
  config :lightning, :ai_assistant_modes, %{
    job: LightningWeb.Live.AiAssistant.Modes.JobCode,
    workflow: LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate,
    custom: MyApp.CustomAIMode
  }
  ```

  ## Returns

  A map where:
  - **Keys** are mode identifiers (atoms) used for selection and routing
  - **Values** are module names implementing the `ModeBehavior` protocol

  ## Examples

      # Default configuration
      ModeRegistry.register_modes()
      # => %{
      #   job: LightningWeb.Live.AiAssistant.Modes.JobCode,
      #   workflow: LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate
      # }

      # With custom mode added
      ModeRegistry.register_modes()
      # => %{
      #   job: LightningWeb.Live.AiAssistant.Modes.JobCode,
      #   workflow: LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate,
      #   analytics: MyApp.AnalyticsMode
      # }
  """
  @spec register_modes() :: %{atom() => module()}
  def register_modes do
    Lightning.Config.ai_assistant_modes()
  end

  @doc """
  Retrieves the handler module for a specific AI Assistant mode.

  Provides the primary lookup mechanism for mode delegation, with built-in
  fallback handling to ensure system stability even when invalid modes are requested.

  ## Parameters

  - `mode` - Mode identifier atom (e.g., `:job`, `:workflow`, `:custom`)

  ## Returns

  The module implementing `ModeBehavior` for the requested mode, or the default
  `JobCode` mode if the requested mode is not found.

  ## Fallback Strategy

  When an unknown mode is requested:
  1. Registry lookup fails for the specified mode
  2. System automatically falls back to `JobCode` mode
  3. User receives basic AI assistance instead of error
  4. Graceful degradation maintains system functionality

  ## Examples

      # Get handler for known mode
      ModeRegistry.get_handler(:job)
      # => LightningWeb.Live.AiAssistant.Modes.JobCode

      # Get handler for workflow mode
      ModeRegistry.get_handler(:workflow)
      # => LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate

      # Fallback for unknown mode
      ModeRegistry.get_handler(:nonexistent)
      # => LightningWeb.Live.AiAssistant.Modes.JobCode (default fallback)

      # Use handler for delegation
      handler = ModeRegistry.get_handler(current_mode)
      {:ok, session} = handler.create_session(assigns, content)
  """
  @spec get_handler(atom()) :: module()
  def get_handler(mode) do
    Map.get(register_modes(), mode, JobCode)
  end

  @doc """
  Returns a comprehensive list of all available modes with their metadata.

  Aggregates metadata from all registered modes to provide rich information
  for UI generation, feature detection, and mode selection interfaces.

  ## Returns

  A list of maps, each containing:
  - `:id` - Mode identifier for programmatic access
  - `:name` - Human-readable mode name for display
  - `:description` - Brief explanation of mode capabilities
  - `:icon` - UI icon class for visual representation
  - `:category` - Optional grouping category
  - `:features` - Optional list of supported features

  ## Examples

      ModeRegistry.available_modes()
      # => [
      #   %{
      #     id: :job,
      #     name: "Job Code Assistant",
      #     description: "Get help with job code, debugging, and adaptors",
      #     icon: "hero-cpu-chip",
      #     category: "development",
      #     features: ["code_assistance", "debugging", "adaptor_guidance"]
      #   },
      #   %{
      #     id: :workflow,
      #     name: "Workflow Builder",
      #     description: "Generate complete workflows from descriptions",
      #     icon: "hero-cpu-chip",
      #     category: "creation",
      #     features: ["template_generation", "yaml_creation"]
      #   }
      # ]

  ## Usage Patterns

      # Generate mode selection dropdown
      available_modes()
      |> Enum.map(fn mode ->
        {mode.name, mode.id}
      end)

      # Filter modes by category
      available_modes()
      |> Enum.filter(&(&1.category == "development"))

      # Find modes with specific features
      available_modes()
      |> Enum.filter(&("template_generation" in (&1.features || [])))
  """
  @spec available_modes() :: [map()]
  def available_modes do
    register_modes()
    |> Enum.map(fn {id, module} ->
      Map.put(module.metadata(), :id, id)
    end)
  end

  @doc """
  Retrieves complete metadata for a specific mode.

  Provides detailed information about a single mode's capabilities,
  configuration, and UI requirements for focused mode operations.

  ## Parameters

  - `mode` - Mode identifier atom to look up

  ## Returns

  A map containing the mode's metadata with the ID field automatically included.
  If the mode is not found, returns metadata for the default mode.

  ## Examples

      # Get metadata for job mode
      ModeRegistry.get_mode_metadata(:job)
      # => %{
      #   id: :job,
      #   name: "Job Code Assistant",
      #   description: "Get help with job code, debugging, and OpenFn adaptors",
      #   icon: "hero-cpu-chip",
      #   category: "development"
      # }

      # Get metadata for workflow mode
      ModeRegistry.get_mode_metadata(:workflow)
      # => %{
      #   id: :workflow,
      #   name: "Workflow Builder",
      #   description: "Generate complete workflows from your descriptions",
      #   icon: "hero-cpu-chip",
      #   category: "creation"
      # }

      # Use metadata for UI rendering
      mode_meta = get_mode_metadata(current_mode)
      render_mode_header(mode_meta.name, mode_meta.icon)
  """
  @spec get_mode_metadata(atom()) :: map()
  def get_mode_metadata(mode) do
    handler = get_handler(mode)
    Map.put(handler.metadata(), :id, mode)
  end

  @doc """
  Checks if a specific mode supports template generation capabilities.

  Provides capability detection for UI features that depend on template
  generation, such as "Apply Template" buttons, template preview panels,
  and workflow export functionality.

  ## Parameters

  - `mode` - Mode identifier atom to check

  ## Returns

  `true` if the mode supports template generation, `false` otherwise.

  ## Examples

      # Check workflow mode (supports templates)
      ModeRegistry.supports_template_generation?(:workflow)
      # => true

      # Check job mode (doesn't support templates)
      ModeRegistry.supports_template_generation?(:job)
      # => false

      # Conditional UI rendering
      if ModeRegistry.supports_template_generation?(current_mode) do
        render_template_actions()
      else
        render_assistance_actions()
      end

      # Filter modes for template features
      template_modes =
        available_modes()
        |> Enum.filter(&supports_template_generation?(&1.id))
  """
  @spec supports_template_generation?(atom()) :: boolean()
  def supports_template_generation?(mode) do
    get_handler(mode).supports_template_generation?()
  end

  @doc """
  Returns the default mode identifier for fallback scenarios.

  Provides a programmatic way to access the default mode used when
  explicit mode selection fails or is unavailable.

  ## Returns

  The mode identifier atom for the default mode (currently `:job`).

  ## Examples

      ModeRegistry.default_mode()
      # => :job

      # Use for initialization
      initial_mode = ModeRegistry.default_mode()
      handler = ModeRegistry.get_handler(initial_mode)
  """
  @spec default_mode() :: atom()
  def default_mode, do: :job

  @doc """
  Validates that a mode exists in the registry.

  Provides explicit validation for mode identifiers before attempting
  operations, enabling better error handling and user feedback.

  ## Parameters

  - `mode` - Mode identifier atom to validate

  ## Returns

  `true` if mode exists in registry, `false` otherwise.

  ## Examples

      ModeRegistry.mode_exists?(:job)
      # => true

      ModeRegistry.mode_exists?(:nonexistent)
      # => false

      # Validation before operation
      if ModeRegistry.mode_exists?(requested_mode) do
        proceed_with_mode(requested_mode)
      else
        show_mode_selection_error()
      end
  """
  @spec mode_exists?(atom()) :: boolean()
  def mode_exists?(mode) do
    Map.has_key?(register_modes(), mode)
  end
end
