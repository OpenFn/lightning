defmodule LightningWeb.AiAssistant.ModeRegistryTest do
  use ExUnit.Case

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
end
