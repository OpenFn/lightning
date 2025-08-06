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
end
