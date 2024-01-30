defmodule Lightning.RunsTest do
  use Lightning.DataCase

  import Lightning.Factories
  import Mock
  import Ecto.Query

  alias Lightning.WorkOrders
  alias Lightning.Run
  alias Lightning.Runs
  alias Lightning.Invocation

  describe "enqueue/1" do
    test "enqueues a run" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        build(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      assert {:ok, queued_run} = Runs.enqueue(run)

      assert queued_run.id == run.id
      assert queued_run.state == :available
    end
  end

  describe "claim/1" do
    test "claims a run from the queue" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      {:ok, %{runs: [run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      assert {:ok, [claimed]} = Runs.claim()

      assert claimed.id == run.id
      assert claimed.state == :claimed

      assert {:ok, []} = Runs.claim()
    end

    test "claims with demand" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      [run_1, run_2, run_3] =
        1..3
        |> Enum.map(fn _ ->
          {:ok, %{runs: [run]}} =
            WorkOrders.create_for(trigger,
              workflow: workflow,
              dataclip: params_with_assocs(:dataclip)
            )

          run
        end)

      assert {:ok, [claimed_1, claimed_2]} = Runs.claim(2)

      assert claimed_1.id == run_1.id
      assert claimed_1.state == :claimed
      assert claimed_2.id == run_2.id
      assert claimed_2.state == :claimed

      assert {:ok, [claimed_3]} = Runs.claim(2)

      assert claimed_3.id == run_3.id
      assert claimed_3.state == :claimed
    end

    test "claims with demand for all immediate run" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      [second_last_run, last_run] =
        Enum.map(1..2, fn _i ->
          WorkOrders.create_for(trigger,
            workflow: workflow,
            dataclip: params_with_assocs(:dataclip)
          )
          |> then(fn {:ok, %{runs: [run]}} -> run end)
        end)

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      runs =
        Map.new(1..4, fn i ->
          build(:run,
            work_order: work_order,
            starting_trigger: trigger,
            dataclip: dataclip,
            priority: :immediate
          )
          |> Runs.enqueue()
          |> then(fn {:ok, run} -> {i, run} end)
        end)

      assert {:ok, [claimed_1, claimed_2]} = Runs.claim(2)

      assert claimed_1.id == runs[1].id
      assert claimed_1.state == :claimed
      assert claimed_2.id == runs[2].id
      assert claimed_2.state == :claimed

      assert {:ok, [claimed_3]} = Runs.claim()

      assert claimed_3.id == runs[3].id
      assert claimed_3.state == :claimed

      assert {:ok, [claimed_4, claimed_5]} = Runs.claim(2)

      assert claimed_4.id in [runs[4].id, second_last_run.id]
      assert claimed_4.state == :claimed

      assert claimed_5.id != claimed_4.id
      assert claimed_5.id in [runs[4].id, second_last_run.id]
      assert claimed_5.state == :claimed

      assert {:ok, [claimed_6]} = Runs.claim(2)

      assert claimed_6.id == last_run.id
      assert claimed_6.state == :claimed
    end
  end

  describe "dequeue/1" do
    test "removes a run from the queue" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      {:ok, %{runs: [run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      assert {:ok, dequeued} = Runs.dequeue(run)

      refute dequeued |> Repo.reload()
    end
  end

  describe "start_step/1" do
    test "creates a new step for a run" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Runs.start_step(%{
          "run_id" => run.id,
          "job_id" => Ecto.UUID.generate(),
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors
      refute {:run_id, {"does not exist", []}} in changeset.errors

      # both run_id and job_id doesn't exist
      {:error, changeset} =
        Runs.start_step(%{
          "run_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors
      assert {:run_id, {"does not exist", []}} in changeset.errors

      Lightning.WorkOrders.subscribe(workflow.project_id)

      {:ok, step} =
        Runs.start_step(%{
          "run_id" => run.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => _step_id = Ecto.UUID.generate()
        })

      assert step.started_at, "The step has been marked as started"

      assert Repo.get_by(Lightning.RunStep, step_id: step.id),
             "There is a corresponding RunStep linking it to the run"

      run_id = run.id

      assert_received %Lightning.WorkOrders.Events.RunUpdated{
        run: %{id: ^run_id}
      }
    end
  end

  describe "complete_step/1" do
    test "marks a step as finished" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      step =
        insert(:step, runs: [run], job: job, input_dataclip: dataclip)

      {:ok, step} =
        Runs.complete_step(%{
          step_id: step.id,
          reason: "success",
          output_dataclip: ~s({"foo": "bar"}),
          output_dataclip_id: Ecto.UUID.generate(),
          run_id: run.id,
          project_id: workflow.project_id
        })

      step =
        step
        |> Repo.preload(output_dataclip: Invocation.Query.dataclip_with_body())

      assert step.exit_reason == "success"
      assert step.output_dataclip.body == %{"foo" => "bar"}
    end

    test "with invalid data returns error changeset" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      step =
        insert(:step, runs: [run], job: job, input_dataclip: dataclip)

      assert {:error, %Ecto.Changeset{}} =
               Runs.complete_step(%{
                 step_id: step.id
               })
    end

    test "with an non-existant step returns an error changeset" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      assert {:error, %Ecto.Changeset{errors: [step_id: {"not found", []}]}} =
               Runs.complete_step(%{
                 step_id: Ecto.UUID.generate(),
                 reason: "success",
                 output_dataclip: ~s({"foo": "bar"}),
                 output_dataclip_id: Ecto.UUID.generate(),
                 run_id: run.id,
                 project_id: workflow.project_id
               })
    end
  end

  describe "get_input" do
    setup context do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      dataclip =
        case context.dataclip_type do
          :http_request ->
            insert(:http_request_dataclip)

          :step_result ->
            insert(:dataclip,
              body: %{"i'm" => ["a", "dataclip"]},
              type: :step_result
            )
        end

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      %{run: run}
    end

    @tag dataclip_type: :step_result
    test "returns the body of a dataclip", %{run: run} do
      assert Runs.get_input(run) == ~s({"i'm": ["a", "dataclip"]})
    end

    @tag dataclip_type: :http_request
    test "returns headers and body for http_request", %{run: run} do
      assert Runs.get_input(run) ==
               ~s({"data": {"foo": "bar"}, "request": {"headers": {"content-type": "application/json"}}})
    end
  end

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

    test "marks a run as started",
         %{run: run, workorder_id: workorder_id} do
      assert {:ok, %Run{started_at: started_at}} =
               Runs.start_run(run)

      assert DateTime.compare(started_at, DateTime.utc_now()) == :lt

      assert_received %Lightning.WorkOrders.Events.WorkOrderUpdated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "indicates if a response was unsuccessful", %{run: run} do
      with_mock(
        Lightning.Repo,
        transaction: fn _multi -> {:error, nil, %Ecto.Changeset{}, nil} end
      ) do
        assert Runs.start_run(run) == {:error, %Ecto.Changeset{}}
      end
    end

    test "triggers a metric if starting the run was successful",
         %{run: run} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:domain, :run, :queue]]
        )

      {:ok,
       %Run{
         started_at: started_at,
         inserted_at: inserted_at
       }} =
        Runs.start_run(run)

      delay = DateTime.diff(started_at, inserted_at, :millisecond)

      assert_received {
        [:domain, :run, :queue],
        ^ref,
        %{delay: ^delay},
        %{}
      }
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

  describe "complete_run/1" do
    test "marks a run as complete" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        workorder =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      # Make another run to ensure the updating doesn't include other
      # runs.
      %{runs: [_run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Runs.complete_run(run, %{state: :success})

      assert {:state,
              {"cannot mark run success that has not been claimed by a worker",
               []}} in changeset.errors

      {:ok, run} =
        Repo.update(run |> Ecto.Changeset.change(state: :claimed))

      # TODO: test that the workorder has it's state updated

      {:ok, run} = Runs.start_run(run)

      assert WorkOrders.get(run.work_order_id).state == :running

      Lightning.WorkOrders.subscribe(workflow.project_id)

      {:ok, run} = Runs.complete_run(run, %{state: :success})

      assert run.state == :success
      assert DateTime.after?(DateTime.utc_now(), run.finished_at)

      workorder_id = workorder.id

      assert_received %Lightning.WorkOrders.Events.WorkOrderUpdated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "blocks completion from :available if new state is :lost" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, run} =
        run
        |> Ecto.Changeset.change(state: :available)
        |> Repo.update()

      {:error, changeset} =
        Runs.complete_run(run, %{state: :lost, error_type: "Lost"})

      assert changeset.errors == [
               state:
                 {"cannot mark run lost that has not been claimed by a worker",
                  []}
             ]
    end

    test "allows completion from :claimed if new state is :lost" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, run} =
        run
        |> Ecto.Changeset.change(state: :claimed)
        |> Repo.update()

      {:ok, run} =
        Runs.complete_run(run, %{state: :lost, error_type: "Lost"})

      assert run.state == :lost
    end

    test "returns error if state is not present" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, run} =
        run
        |> Ecto.Changeset.change(state: :started)
        |> Repo.update()

      {:error, changeset} =
        Runs.complete_run(run, %{})

      assert changeset.errors == [
               state: {"can't be blank", [validation: :required]}
             ]
    end

    test "returns error if state is not identifiable" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, run} =
        run
        |> Ecto.Changeset.change(state: :started)
        |> Repo.update()

      {:error, changeset} =
        Runs.complete_run(run, %{state: "some_unknown_state"})

      assert [
               state:
                 {"is invalid",
                  [
                    type: {:parameterized, Ecto.Enum, _allowed},
                    validation: :cast
                  ]}
             ] = changeset.errors
    end
  end

  describe "append_run_log/3" do
    test "adds a log line to a run" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Runs.append_run_log(run, %{source: "fooo-ooooo"})

      assert {:source,
              {"should be at most %{count} character(s)",
               [count: 8, validation: :length, kind: :max, type: :string]}} in changeset.errors

      assert {:message, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:timestamp, {"can't be blank", [validation: :required]}} in changeset.errors

      {:error, changeset} =
        Runs.append_run_log(run, %{
          step_id: Ecto.UUID.generate(),
          message: "I'm a log line",
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert {:step_id, {"must be associated with the run", []}} in changeset.errors

      {:ok, _log_line} =
        Runs.append_run_log(run, %{
          message: "I'm a log line",
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      step =
        insert(:step, runs: [run], job: job, input_dataclip: dataclip)

      {:ok, log_line} =
        Runs.append_run_log(run, %{
          message: "I'm another log line",
          step_id: step.id,
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      log_line =
        Repo.get_by(Invocation.LogLine, id: log_line.id)
        |> Repo.preload(:step)

      assert log_line.step.id == step.id
    end

    test "adding json objects as messages" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [_job]} = workflow = insert(:simple_workflow)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, log_line} =
        Runs.append_run_log(run, %{
          message: [%{"foo" => "bar"}, "hello there"],
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert log_line.message == ~s<{"foo":"bar"} hello there>

      {:ok, log_line} =
        Runs.append_run_log(run, %{
          message: %{"foo" => "bar"},
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert log_line.message == ~s<{"foo":"bar"}>
    end
  end

  describe "mark_unfinished_steps_lost/1" do
    @tag :capture_log
    test "marks unfinished steps as lost" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      finished_step =
        insert(:step,
          runs: [run],
          finished_at: DateTime.utc_now(),
          exit_reason: "success"
        )

      unfinished_step = insert(:step, runs: [run])

      Runs.mark_run_lost(run)

      reloaded_finished_step = Repo.get(Invocation.Step, finished_step.id)
      reloaded_unfinished_step = Repo.get(Invocation.Step, unfinished_step.id)

      assert reloaded_finished_step.exit_reason == "success"
      assert reloaded_unfinished_step.exit_reason == "lost"

      assert reloaded_unfinished_step.finished_at != nil
    end
  end

  describe "wipe_dataclips/1" do
    test "clears the dataclip body and request fields" do
      project = insert(:project)
      dataclip = insert(:http_request_dataclip, project: project)

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      assert dataclip.body
      assert dataclip.request
      refute dataclip.wiped_at

      :ok = Runs.wipe_dataclips(run)

      # dataclip body is cleared
      query = from(Invocation.Dataclip, select: [:wiped_at, :body, :request])

      updated_dataclip = Lightning.Repo.get(query, dataclip.id)

      assert updated_dataclip.wiped_at ==
               DateTime.utc_now() |> DateTime.truncate(:second)

      refute updated_dataclip.body
      refute updated_dataclip.request
    end
  end
end
