defmodule Lightning.Projects.SandboxPromExPluginTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.SandboxPromExPlugin

  describe "event_metrics/1" do
    test "returns a single event group with correct name" do
      assert [
               %PromEx.MetricTypes.Event{
                 group_name: :lightning_sandbox_event_metrics
               }
             ] = SandboxPromExPlugin.event_metrics([])
    end

    test "returns five counter metrics" do
      [%{metrics: metrics}] = SandboxPromExPlugin.event_metrics([])

      assert Enum.count(metrics) == 5

      assert Enum.all?(metrics, fn metric ->
               match?(%Telemetry.Metrics.Counter{}, metric)
             end)
    end

    test "contains sandbox created counter metric" do
      [%{metrics: metrics}] = SandboxPromExPlugin.event_metrics([])

      metric =
        find_metric(metrics, [:lightning, :sandbox, :created, :count])

      assert %Telemetry.Metrics.Counter{
               name: [:lightning, :sandbox, :created, :count],
               description: "Count of sandbox projects created.",
               tags: []
             } = metric
    end

    test "contains sandbox merged counter metric" do
      [%{metrics: metrics}] = SandboxPromExPlugin.event_metrics([])

      metric =
        find_metric(metrics, [:lightning, :sandbox, :merged, :count])

      assert %Telemetry.Metrics.Counter{
               name: [:lightning, :sandbox, :merged, :count],
               description: "Count of sandbox projects merged into targets.",
               tags: []
             } = metric
    end

    test "contains sandbox deleted counter metric" do
      [%{metrics: metrics}] = SandboxPromExPlugin.event_metrics([])

      metric =
        find_metric(metrics, [:lightning, :sandbox, :deleted, :count])

      assert %Telemetry.Metrics.Counter{
               name: [:lightning, :sandbox, :deleted, :count],
               description: "Count of sandbox projects manually deleted.",
               tags: []
             } = metric
    end

    test "contains workflow saved counter metric with is_sandbox tag" do
      [%{metrics: metrics}] = SandboxPromExPlugin.event_metrics([])

      metric = find_metric(metrics, [:lightning, :workflow, :saved, :count])

      assert %Telemetry.Metrics.Counter{
               name: [:lightning, :workflow, :saved, :count],
               description: "Count of workflow saves, tagged by project type.",
               tags: [:is_sandbox]
             } = metric
    end

    test "contains provisioner import counter metric with is_sandbox tag" do
      [%{metrics: metrics}] = SandboxPromExPlugin.event_metrics([])

      metric =
        find_metric(metrics, [:lightning, :provisioner, :import, :count])

      assert %Telemetry.Metrics.Counter{
               name: [:lightning, :provisioner, :import, :count],
               description:
                 "Count of provisioner imports, tagged by project type.",
               tags: [:is_sandbox]
             } = metric
    end

    defp find_metric(metrics, metric_name) do
      Enum.find(metrics, &(&1.name == metric_name))
    end
  end

  describe "fire_sandbox_created_event/0" do
    test "emits telemetry event with count of 1" do
      event = [:lightning, :sandbox, :created]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      SandboxPromExPlugin.fire_sandbox_created_event()

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{}
      }
    end
  end

  describe "fire_sandbox_merged_event/0" do
    test "emits telemetry event with count of 1" do
      event = [:lightning, :sandbox, :merged]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      SandboxPromExPlugin.fire_sandbox_merged_event()

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{}
      }
    end
  end

  describe "fire_sandbox_deleted_event/0" do
    test "emits telemetry event with count of 1" do
      event = [:lightning, :sandbox, :deleted]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      SandboxPromExPlugin.fire_sandbox_deleted_event()

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{}
      }
    end
  end

  describe "fire_workflow_saved_event/1" do
    test "emits telemetry event with is_sandbox: true" do
      event = [:lightning, :workflow, :saved]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      SandboxPromExPlugin.fire_workflow_saved_event(true)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{is_sandbox: true}
      }
    end

    test "emits telemetry event with is_sandbox: false" do
      event = [:lightning, :workflow, :saved]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      SandboxPromExPlugin.fire_workflow_saved_event(false)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{is_sandbox: false}
      }
    end
  end

  describe "fire_provisioner_import_event/1" do
    test "emits telemetry event with is_sandbox: true" do
      event = [:lightning, :provisioner, :import]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      SandboxPromExPlugin.fire_provisioner_import_event(true)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{is_sandbox: true}
      }
    end

    test "emits telemetry event with is_sandbox: false" do
      event = [:lightning, :provisioner, :import]
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      SandboxPromExPlugin.fire_provisioner_import_event(false)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{is_sandbox: false}
      }
    end
  end
end
