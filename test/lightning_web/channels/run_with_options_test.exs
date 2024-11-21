defmodule LightningWeb.RunWithOptionsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Runs
  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias LightningWeb.RunWithOptions

  describe "rendering a run" do
    test "renders a workflow using a snapshot" do
      user = insert(:user)

      {:ok, %{triggers: [trigger], jobs: [job], edges: [edge]} = workflow} =
        insert(:simple_workflow)
        |> Workflow.touch()
        |> Workflows.save_workflow(user)

      %{runs: [run]} =
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
          "options" => %{"output_dataclips" => true, "run_timeout_ms" => 300_000}
        }

      run = Runs.get_for_worker(run.id)

      assert RunWithOptions.render(run)
             |> Jason.encode!()
             |> Jason.decode!() ==
               expected_result

      {:ok, workflow} =
        workflow
        |> Workflows.change_workflow(%{jobs: [%{id: job.id, body: "foo()"}]})
        |> Workflows.save_workflow(user)

      %{runs: [run]} =
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
          "options" => %{"output_dataclips" => true, "run_timeout_ms" => 300_000}
        }

      assert RunWithOptions.render(run)
             |> Jason.encode!()
             |> Jason.decode!() ==
               expected_result
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
  end
end
