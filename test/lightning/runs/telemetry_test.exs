defmodule Lightning.Runs.TelemetryTest do
  use Lightning.DataCase, async: false

  import Mock
  import Lightning.Factories

  alias Lightning.Runs

  describe "start_run/1" do
    setup do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        workorder =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, run} =
        Repo.update(run |> Ecto.Changeset.change(state: :claimed))

      Lightning.WorkOrders.subscribe(workflow.project_id)

      %{run: run, workorder_id: workorder.id}
    end

    test "does not trigger a metric if starting the run was unsuccessful",
         %{run: run} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:domain, :run, :queue]]
        )

      with_mock(
        Lightning.Repo,
        transaction: fn _multi -> {:error, nil, nil, nil} end
      ) do
        Runs.start_run(run)
      end

      refute_received {
        [:domain, :run, :queue],
        ^ref,
        %{delay: _delay},
        %{}
      }
    end
  end
end
