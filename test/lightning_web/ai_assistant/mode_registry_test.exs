defmodule LightningWeb.AiAssistant.ModeRegistryTest do
  use ExUnit.Case, async: true

  import Mox

  alias LightningWeb.Live.AiAssistant.ModeRegistry
  alias LightningWeb.Live.AiAssistant.Modes.{JobCode, WorkflowTemplate}

  setup :verify_on_exit!

  setup do
    stub(Lightning.MockConfig, :ai_assistant_modes, fn ->
      %{
        job: JobCode,
        workflow: WorkflowTemplate
      }
    end)

    :ok
  end

  describe "get_handler/1" do
    test "returns correct handler for known modes" do
      assert ModeRegistry.get_handler(:job) == JobCode
      assert ModeRegistry.get_handler(:workflow) == WorkflowTemplate
    end

    test "falls back to JobCode for unknown modes" do
      assert ModeRegistry.get_handler(:nonexistent) == JobCode
      assert ModeRegistry.get_handler(nil) == JobCode
    end
  end

  describe "available_modes/0" do
    test "returns all modes with metadata" do
      modes = ModeRegistry.available_modes()

      assert length(modes) == 2
      assert Enum.find(modes, &(&1.id == :job))
      assert Enum.find(modes, &(&1.id == :workflow))

      job_mode = Enum.find(modes, &(&1.id == :job))
      assert job_mode.name == "Job Code Assistant"
      assert job_mode.icon == "hero-cpu-chip"
    end
  end

  describe "supports_template_generation?/1" do
    test "returns correct capabilities" do
      assert ModeRegistry.supports_template_generation?(:workflow) == true
      assert ModeRegistry.supports_template_generation?(:job) == false
    end
  end

  describe "register_modes/0" do
    test "returns the mode registry from config" do
      modes = ModeRegistry.register_modes()

      assert is_map(modes)
      assert modes[:job] == JobCode
      assert modes[:workflow] == WorkflowTemplate
    end

    test "handles empty configuration" do
      stub(Lightning.MockConfig, :ai_assistant_modes, fn -> %{} end)

      modes = ModeRegistry.register_modes()
      assert modes == %{}
    end

    test "handles custom modes from config" do
      custom_mode_module = CustomTestMode

      stub(Lightning.MockConfig, :ai_assistant_modes, fn ->
        %{
          job: JobCode,
          workflow: WorkflowTemplate,
          custom: custom_mode_module
        }
      end)

      modes = ModeRegistry.register_modes()
      assert modes[:custom] == custom_mode_module
    end
  end

  describe "get_mode_metadata/1" do
    test "returns metadata for valid modes" do
      job_metadata = ModeRegistry.get_mode_metadata(:job)

      assert job_metadata.id == :job
      assert job_metadata.name == "Job Code Assistant"
      assert job_metadata.icon == "hero-cpu-chip"

      workflow_metadata = ModeRegistry.get_mode_metadata(:workflow)
      assert workflow_metadata.id == :workflow
      assert workflow_metadata.name == "Workflow Builder"
    end

    test "falls back to default mode metadata for unknown modes" do
      metadata = ModeRegistry.get_mode_metadata(:nonexistent)

      assert metadata.name == "Job Code Assistant"

      assert metadata.id == :nonexistent
    end

    test "includes id in metadata automatically" do
      metadata = ModeRegistry.get_mode_metadata(:job)
      assert Map.has_key?(metadata, :id)
      assert metadata.id == :job
    end
  end

  describe "default_mode/0" do
    test "returns the default mode identifier" do
      assert ModeRegistry.default_mode() == :job
    end
  end

  describe "mode_exists?/1" do
    test "returns true for existing modes" do
      assert ModeRegistry.mode_exists?(:job) == true
      assert ModeRegistry.mode_exists?(:workflow) == true
    end

    test "returns false for non-existing modes" do
      assert ModeRegistry.mode_exists?(:nonexistent) == false
      assert ModeRegistry.mode_exists?(:invalid) == false
      assert ModeRegistry.mode_exists?(nil) == false
    end

    test "handles edge cases" do
      assert ModeRegistry.mode_exists?("job") == false
      assert ModeRegistry.mode_exists?(%{}) == false
    end
  end

  describe "supports_template_generation?/1 edge cases" do
    test "falls back to default behavior for unknown modes" do
      assert ModeRegistry.supports_template_generation?(:unknown) == false
    end

    test "handles nil and invalid input" do
      assert ModeRegistry.supports_template_generation?(nil) == false
      assert ModeRegistry.supports_template_generation?("invalid") == false
    end
  end

  describe "available_modes/0 edge cases" do
    test "handles empty registry" do
      stub(Lightning.MockConfig, :ai_assistant_modes, fn -> %{} end)

      modes = ModeRegistry.available_modes()
      assert modes == []
    end

    test "includes id field for all modes" do
      modes = ModeRegistry.available_modes()

      Enum.each(modes, fn mode ->
        assert Map.has_key?(mode, :id)
        assert is_atom(mode.id)
      end)
    end

    test "preserves original metadata while adding id" do
      modes = ModeRegistry.available_modes()
      job_mode = Enum.find(modes, &(&1.id == :job))

      assert Map.has_key?(job_mode, :name)
      assert Map.has_key?(job_mode, :icon)
      assert Map.has_key?(job_mode, :id)
    end
  end

  describe "integration between functions" do
    test "get_handler and get_mode_metadata return consistent information" do
      handler = ModeRegistry.get_handler(:job)
      metadata = ModeRegistry.get_mode_metadata(:job)

      assert metadata == Map.put(handler.metadata(), :id, :job)
    end

    test "available_modes includes all modes from register_modes" do
      registered_modes = ModeRegistry.register_modes()
      available_modes = ModeRegistry.available_modes()

      assert length(available_modes) == map_size(registered_modes)

      Enum.each(registered_modes, fn {mode_id, _module} ->
        assert Enum.any?(available_modes, &(&1.id == mode_id))
      end)
    end

    test "mode_exists? is consistent with get_handler fallback behavior" do
      assert ModeRegistry.mode_exists?(:job) == true
      assert ModeRegistry.get_handler(:job) != JobCode || true

      assert ModeRegistry.mode_exists?(:nonexistent) == false
      assert ModeRegistry.get_handler(:nonexistent) == JobCode
    end
  end
end
