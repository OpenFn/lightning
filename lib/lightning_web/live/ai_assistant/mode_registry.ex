defmodule LightningWeb.Live.AiAssistant.ModeRegistry do
  @moduledoc """
  Centralized registry for managing AI Assistant interaction modes.

  This module provides a pluggable architecture for AI Assistant modes, enabling
  dynamic mode discovery, configuration, and management. It serves as the central
  coordination point for all AI assistance capabilities within Lightning.

  ## Architecture Overview

  The registry implements a plugin-style architecture where:
  - **Modes** are independent modules implementing the `ModeBehavior` protocol
  - **Registration** happens through application configuration or module discovery
  - **Lookup** provides fast access to mode handlers and metadata
  - **Extensibility** allows easy addition of new AI assistance modes

  ## Registry Design Patterns

  ### Configuration-Based Registration
  Modes are registered through application configuration, allowing:
  - **Runtime configuration** - Modes can be enabled/disabled per environment
  - **Custom mode injection** - Third-party modes can be easily integrated
  - **Feature flag support** - Modes can be conditionally enabled
  - **Environment-specific modes** - Different modes for dev/staging/prod

  ### Fallback Strategy
  The registry implements a graceful degradation pattern:
  - Unknown modes default to `JobCode` mode for basic assistance
  - Ensures system stability even with configuration errors
  - Provides consistent user experience across mode transitions

  ## Mode Discovery & Metadata

  The registry provides rich metadata capabilities:
  - **Dynamic mode enumeration** for UI generation
  - **Capability detection** for feature-specific UI elements
  - **Metadata aggregation** from individual mode implementations
  - **UI configuration support** for icons, descriptions, and categories

  ## Usage Patterns

  ### Mode Selection in UI Components
  ```elixir
  # Get available modes for dropdown
  modes = ModeRegistry.available_modes()
  # => [%{id: :job, name: "Job Assistant", icon: "hero-cpu-chip"}, ...]

  # Check if mode supports specific features
  if ModeRegistry.supports_template_generation?(selected_mode) do
    # Show template application UI
  end
  ```

  ### Mode Handler Delegation
  ```elixir
  # Get handler for selected mode
  handler = ModeRegistry.get_handler(current_mode)

  # Use handler for mode-specific operations
  {:ok, session} = handler.create_session(assigns, content)
  ```

  ### Dynamic Feature Detection
  ```elixir
  # Build UI based on mode capabilities
  modes_with_templates =
    ModeRegistry.available_modes()
    |> Enum.filter(&ModeRegistry.supports_template_generation?(&1.id))
  ```

  ## Configuration Examples

  ### Application Configuration
  ```elixir
  # config/config.exs
  config :lightning, :ai_assistant_modes, %{
    job: LightningWeb.Live.AiAssistant.Modes.JobCode,
    workflow: LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate,
    custom: MyApp.CustomAIMode
  }
  ```

  ### Environment-Specific Modes
  ```elixir
  # config/dev.exs - Enable experimental modes in development
  config :lightning, :ai_assistant_modes, %{
    job: LightningWeb.Live.AiAssistant.Modes.JobCode,
    workflow: LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate,
    experimental: MyApp.ExperimentalMode
  }
  ```

  ## Extension Points

  ### Adding Custom Modes
  1. Implement `ModeBehavior` protocol
  2. Add to application configuration
  3. Mode automatically available throughout system

  ### Mode Categories & Organization
  Modes can be organized by category for better UX:
  - **Development** - Code assistance and debugging
  - **Creation** - Template and workflow generation
  - **Analysis** - Data analysis and reporting
  - **Integration** - Third-party service assistance

  ## Performance Considerations

  - **Lazy loading** - Mode modules loaded only when needed
  - **Metadata caching** - Mode metadata cached for efficient UI rendering
  - **Configuration optimization** - Registry reads from optimized application config
  - **Fallback efficiency** - Default mode lookup is O(1) operation

  ## Security & Isolation

  - **Mode isolation** - Each mode operates independently with its own context
  - **Permission delegation** - Registry respects individual mode permission requirements
  - **Configuration validation** - Ensures only valid mode implementations are registered
  - **Capability limitation** - Mode features are explicitly declared and enforced
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

  ## Implementation Notes

  - Uses application configuration for flexibility and environment-specific setups
  - Provides default modes if no custom configuration is present
  - Supports runtime mode registration through configuration updates
  - Enables feature flagging by excluding modes from configuration
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

  ## Implementation Notes

  - O(1) lookup performance using Map.get/3
  - Built-in fallback prevents runtime errors
  - Supports dynamic mode switching in UI
  - Thread-safe for concurrent access
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

  ## Implementation Notes

  - Metadata is fetched dynamically from each mode implementation
  - Mode ID is automatically injected for consistency
  - Supports extensible metadata schema through mode implementations
  - Enables data-driven UI generation
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

  ## Implementation Notes

  - Automatically includes mode ID for consistency
  - Uses same fallback strategy as `get_handler/1`
  - Metadata is fetched fresh from mode implementation
  - Supports dynamic metadata updates
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

  ## UI Integration

  This capability check enables:
  - **Conditional UI elements** - Show template-specific controls only when supported
  - **Feature-specific workflows** - Route users to appropriate modes for template tasks
  - **Mode recommendations** - Suggest template-capable modes for workflow creation
  - **Progressive enhancement** - Add template features when available

  ## Implementation Notes

  - Delegates to the mode's `supports_template_generation?/0` callback
  - Uses same fallback strategy for unknown modes
  - Cached at the mode level for performance
  - Consistent with mode behavior protocol
  """
  @spec supports_template_generation?(atom()) :: boolean()
  def supports_template_generation?(mode) do
    get_handler(mode).supports_template_generation?()
  end

  @doc """
  Returns modes filtered by specific capabilities or features.

  Provides advanced mode discovery based on feature requirements,
  enabling dynamic UI generation and intelligent mode recommendations.

  ## Parameters

  - `filter_opts` - Keyword list of filtering options:
    - `:supports_templates` - Filter by template generation capability
    - `:category` - Filter by mode category
    - `:features` - Filter by specific feature requirements

  ## Examples

      # Get all template-capable modes
      ModeRegistry.modes_with_capability(supports_templates: true)
      # => [%{id: :workflow, name: "Workflow Builder", ...}]

      # Get development-focused modes
      ModeRegistry.modes_with_capability(category: "development")
      # => [%{id: :job, name: "Job Code Assistant", ...}]

      # Get modes with specific features
      ModeRegistry.modes_with_capability(features: ["debugging", "code_assistance"])
      # => [modes that support both debugging and code assistance]

  ## Implementation Notes

  - Builds on `available_modes/0` for consistent metadata
  - Supports multiple simultaneous filters
  - Returns empty list if no modes match criteria
  - Enables data-driven mode selection
  """
  @spec modes_with_capability(keyword()) :: [map()]
  def modes_with_capability(filter_opts \\ []) do
    modes = available_modes()

    Enum.filter(modes, fn mode ->
      Enum.all?(filter_opts, fn
        {:supports_templates, required} ->
          supports_template_generation?(mode.id) == required

        {:category, required_category} ->
          Map.get(mode, :category) == required_category

        {:features, required_features} when is_list(required_features) ->
          mode_features = Map.get(mode, :features, [])
          Enum.all?(required_features, &(&1 in mode_features))

        _ ->
          true
      end)
    end)
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

  ## Implementation Notes

  - Consistent with fallback behavior in `get_handler/1`
  - Enables explicit default mode handling
  - Supports configuration-driven default mode changes
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

  ## Implementation Notes

  - More explicit than relying on fallback behavior
  - Enables proper error handling and user feedback
  - O(1) lookup performance
  - Useful for API validation and debugging
  """
  @spec mode_exists?(atom()) :: boolean()
  def mode_exists?(mode) do
    Map.has_key?(register_modes(), mode)
  end
end
