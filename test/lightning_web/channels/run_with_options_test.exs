defmodule LightningWeb.RunWithOptionsTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.Runs
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias LightningWeb.RunWithOptions

  describe "rendering a run" do
    setup do
      cache = Lightning.Adaptors.Supervisor.cache_name(Lightning.Adaptors)
      Cachex.clear(cache)

      insert(:adaptor,
        name: "@openfn/language-common",
        source: :npm,
        latest_version: "1.6.2"
      )

      :ok
    end

    test "renders a workflow using a snapshot" do
      user = insert(:user)

      {:ok, %{triggers: [trigger], jobs: [job], edges: [edge]} = workflow} =
        insert(:simple_workflow)
        |> Workflow.touch()
        |> Workflows.save_workflow(user)

      %{id: work_order_id, runs: [run]} =
        work_order_for(trigger,
          workflow: workflow,
          dataclip: dataclip = insert(:dataclip)
        )
        |> insert()

      expected_result =
        %{
          "dataclip_id" => dataclip.id,
          "edges" => [
            %{
              "condition" => "always",
              "enabled" => edge.enabled,
              "id" => edge.id,
              "source_job_id" => edge.source_job_id,
              "source_trigger_id" => edge.source_trigger_id,
              "target_job_id" => edge.target_job_id
            }
          ],
          "id" => run.id,
          "project_id" => workflow.project_id,
          "jobs" => [
            %{
              "adaptor" => "@openfn/language-common@1.6.2",
              "body" => job.body,
              "credential_id" => nil,
              "id" => job.id,
              "name" => job.name
            }
          ],
          "starting_node_id" => trigger.id,
          "triggers" => [%{"id" => trigger.id}],
          "options" => %{"output_dataclips" => true, "run_timeout_ms" => 300_000},
          "meta" => %{
            "work_order_id" => work_order_id,
            "workflow_id" => workflow.id,
            "project_id" => workflow.project_id
          }
        }

      run = Runs.get_for_worker(run.id)

      assert {:ok, plan} = RunWithOptions.render(run)
      assert plan |> Jason.encode!() |> Jason.decode!() == expected_result

      {:ok, workflow} =
        workflow
        |> Workflows.change_workflow(%{jobs: [%{id: job.id, body: "foo()"}]})
        |> Workflows.save_workflow(user)

      %{id: work_order_id, runs: [run]} =
        work_order_for(trigger,
          workflow: workflow,
          dataclip: dataclip = insert(:dataclip)
        )
        |> insert()

      run = Runs.get_for_worker(run.id)

      expected_result =
        %{
          "dataclip_id" => dataclip.id,
          "edges" => [
            %{
              "condition" => "always",
              "enabled" => edge.enabled,
              "id" => edge.id,
              "source_job_id" => edge.source_job_id,
              "source_trigger_id" => edge.source_trigger_id,
              "target_job_id" => edge.target_job_id
            }
          ],
          "id" => run.id,
          "project_id" => workflow.project_id,
          "jobs" => [
            %{
              "adaptor" => "@openfn/language-common@1.6.2",
              "body" => "foo()",
              "credential_id" => nil,
              "id" => job.id,
              "name" => job.name
            }
          ],
          "starting_node_id" => trigger.id,
          "triggers" => [%{"id" => trigger.id}],
          "options" => %{"output_dataclips" => true, "run_timeout_ms" => 300_000},
          "meta" => %{
            "work_order_id" => work_order_id,
            "workflow_id" => workflow.id,
            "project_id" => workflow.project_id
          }
        }

      assert {:ok, plan} = RunWithOptions.render(run)
      assert plan |> Jason.encode!() |> Jason.decode!() == expected_result
    end

    test "returns the adaptor lookup error when a job's @latest cannot be resolved" do
      user = insert(:user)

      {:ok, %{triggers: [trigger], jobs: [job]} = workflow} =
        insert(:simple_workflow)
        |> Workflow.touch()
        |> Workflows.save_workflow(user)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: insert(:dataclip))
        |> insert()

      run = Runs.get_for_worker(run.id)

      snapshot_job =
        Enum.find(run.snapshot.jobs, &(&1.id == job.id))
        |> Map.put(:adaptor, "@openfn/language-never-published@latest")

      run = put_in(run.snapshot.jobs, [snapshot_job])

      assert {:error, :not_found} = RunWithOptions.render(run)
    end
  end

  describe "options_for_worker/1" do
    test "converts RunOptions to options for the worker" do
      lightning_options = %Lightning.Runs.RunOptions{
        save_dataclips: true,
        run_timeout_ms: 123
      }

      expected_worker_options = %{
        output_dataclips: true,
        run_timeout_ms: 123
      }

      assert RunWithOptions.options_for_worker(lightning_options) ==
               expected_worker_options
    end

    test "converts enable_job_logs correctly for the worker" do
      # when enable_job_logs is true
      lightning_options = %Lightning.Runs.RunOptions{
        save_dataclips: true,
        run_timeout_ms: 123,
        enable_job_logs: true
      }

      # job_log_level is not included in the worker option
      assert RunWithOptions.options_for_worker(lightning_options) ==
               %{
                 output_dataclips: true,
                 run_timeout_ms: 123
               }

      # when enable_job_logs is false
      lightning_options = %Lightning.Runs.RunOptions{
        save_dataclips: true,
        run_timeout_ms: 123,
        enable_job_logs: false
      }

      # job_log_level is set to "none" in the worker option
      assert RunWithOptions.options_for_worker(lightning_options) ==
               %{
                 output_dataclips: true,
                 run_timeout_ms: 123,
                 job_log_level: "none"
               }
    end
  end
end
