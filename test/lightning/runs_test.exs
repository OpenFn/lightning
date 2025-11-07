defmodule Lightning.RunsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories
  import Ecto.Query

  alias Ecto.Multi

  alias Lightning.Invocation
  alias Lightning.Run
  alias Lightning.Runs
  alias Lightning.WorkOrders
  alias Lightning.Workflows

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

      assert {:ok, %{run: queued_run}} =
               Multi.new() |> Multi.insert(:run, run) |> Runs.enqueue()

      assert queued_run.id == run.id
      assert queued_run.state == :available
    end
  end

  describe "claim/1" do
    setup do
      %{worker_name: "my.worker.name"}
    end

    test "claims a run from the queue", %{worker_name: worker_name} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      {:ok, %{runs: [run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      assert {:ok, [claimed]} = Runs.claim(worker_name)

      assert claimed.id == run.id
      assert claimed.state == :claimed

      assert {:ok, []} = Runs.claim(worker_name)
    end

    test "persists worker name when claiming", %{worker_name: worker_name} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      {:ok, %{runs: [run]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      Runs.claim(worker_name)

      assert %{worker_name: ^worker_name} = Repo.get!(Run, run.id)
    end

    test "claims a run from the queue having parallel runs disabled", %{
      worker_name: worker_name
    } do
      project1 = insert(:project, concurrency: 1)
      project2 = insert(:project)

      [
        {%{id: run1_id}, _},
        {%{id: run2a_id}, %{trigger: trigger2, workflow: workflow2}},
        {%{id: run3_id}, _}
      ] =
        Enum.map([project1, project2, project1], fn project ->
          %{triggers: [trigger]} =
            workflow =
            insert(:simple_workflow, project: project) |> with_snapshot()

          {:ok, %{runs: [run]}} =
            WorkOrders.create_for(trigger,
              workflow: workflow,
              dataclip: params_with_assocs(:dataclip)
            )

          {run, %{trigger: trigger, workflow: workflow}}
        end)

      assert {:ok, [%{id: ^run1_id, state: :claimed}]} = Runs.claim(worker_name)
      assert {:ok, [%{id: ^run2a_id, state: :claimed}]} = Runs.claim(worker_name)
      assert {:ok, []} = Runs.claim(worker_name)

      {:ok, %{runs: [%{id: run2b_id}]}} =
        WorkOrders.create_for(trigger2,
          workflow: workflow2,
          dataclip: params_with_assocs(:dataclip)
        )

      assert {:ok, [%{id: ^run2b_id, state: :claimed}]} = Runs.claim(worker_name)

      Repo.get!(Run, run1_id)
      |> Ecto.Changeset.change(%{state: :success})
      |> Repo.update!()

      assert {:ok, [%{id: ^run3_id, state: :claimed}]} = Runs.claim(worker_name)
    end

    test "claims with demand", %{worker_name: worker_name} do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

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

      assert {:ok, [claimed_1, claimed_2]} = Runs.claim(2, worker_name)

      assert claimed_1.id == run_1.id
      assert claimed_1.state == :claimed
      assert claimed_2.id == run_2.id
      assert claimed_2.state == :claimed

      assert {:ok, [claimed_3]} = Runs.claim(2, worker_name)

      assert claimed_3.id == run_3.id
      assert claimed_3.state == :claimed
    end

    test "claims with demand for all immediate run", %{
      worker_name: worker_name
    } do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

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
          run =
            build(:run,
              work_order: work_order,
              starting_trigger: trigger,
              dataclip: dataclip,
              priority: :immediate
            )

          Multi.new()
          |> Multi.insert(:run, run)
          |> Runs.enqueue()
          |> then(fn {:ok, %{run: run}} -> {i, run} end)
        end)

      assert {:ok, [claimed_1, claimed_2]} = Runs.claim(2, worker_name)

      assert claimed_1.id == runs[1].id
      assert claimed_1.state == :claimed
      assert claimed_2.id == runs[2].id
      assert claimed_2.state == :claimed

      assert {:ok, [claimed_3]} = Runs.claim(worker_name)

      assert claimed_3.id == runs[3].id
      assert claimed_3.state == :claimed

      assert {:ok, [claimed_4, claimed_5]} = Runs.claim(2, worker_name)

      assert claimed_4.id in [runs[4].id, second_last_run.id]
      assert claimed_4.state == :claimed

      assert claimed_5.id != claimed_4.id
      assert claimed_5.id in [runs[4].id, second_last_run.id]
      assert claimed_5.state == :claimed

      assert {:ok, [claimed_6]} = Runs.claim(2, worker_name)

      assert claimed_6.id == last_run.id
      assert claimed_6.state == :claimed
    end
  end

  describe "dequeue/1" do
    test "removes a run from the queue" do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

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

      %{triggers: [trigger], jobs: [job]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Runs.start_step(run, %{
          "job_id" => Ecto.UUID.generate(),
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors
      refute {:run_id, {"does not exist", []}} in changeset.errors

      # both run_id and job_id doesn't exist
      {:error, changeset} =
        Runs.start_step(build(:run, snapshot_id: Ecto.UUID.generate()), %{
          "job_id" => Ecto.UUID.generate(),
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors
      assert {:run_id, {"does not exist", []}} in changeset.errors

      Lightning.WorkOrders.subscribe(workflow.project_id)

      {:ok, step} =
        Runs.start_step(run, %{
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => _step_id = Ecto.UUID.generate()
        })

      assert step.started_at, "The step should be marked as started"
      assert step.snapshot_id == run.snapshot_id

      assert Repo.get_by(Lightning.RunStep, step_id: step.id),
             "There is a corresponding RunStep linking it to the run"

      # Note: start_step no longer broadcasts RunUpdated event
      # The run state doesn't change when a step starts (already in :started state)
      # Instead, a StepStarted event is broadcast for step-level tracking
      refute_received %Lightning.WorkOrders.Events.RunUpdated{}
    end

    test "should not allow referencing job that is not on the snapshot" do
      dataclip = insert(:dataclip)

      %{triggers: [trigger], jobs: [old_job]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

      %{runs: [run_1]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      # Change the workflow to replace the job with another, and save it
      # creating a new snapshot.
      {:ok, %{jobs: [new_job]}} =
        Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
        |> Workflows.save_workflow(insert(:user))

      {:error, changeset} =
        Runs.start_step(run_1, %{
          "job_id" => new_job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors

      {:ok, step} =
        Runs.start_step(run_1, %{
          "job_id" => old_job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert step.job_id == old_job.id
      assert step.snapshot_id == run_1.snapshot_id
    end
  end

  describe "complete_step/2" do
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
      assert Jason.decode!(step.output_dataclip.body) == %{"foo" => "bar"}
    end

    test "wipes the dataclip if erase_all retention policy is specified at the project level when the run is created" do
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      dataclip = insert(:dataclip, project: workflow.project)

      Repo.get(Lightning.Projects.Project, workflow.project_id)
      |> Ecto.Changeset.change(retention_policy: :erase_all)
      |> Repo.update()

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      assert %Lightning.Runs.RunOptions{
               save_dataclips: false,
               run_timeout_ms: 300_000
             } = run.options

      step =
        insert(:step, runs: [run], job: job, input_dataclip: dataclip)

      Lightning.Stub.freeze_time(~U[2024-05-05 12:34:56Z])

      {:ok, step} =
        Runs.complete_step(
          %{
            step_id: step.id,
            reason: "success",
            output_dataclip: ~s({"foo": "bar"}),
            output_dataclip_id: Ecto.UUID.generate(),
            run_id: run.id,
            project_id: workflow.project_id
          },
          run.options
        )

      step =
        step
        |> Repo.preload(output_dataclip: Invocation.Query.dataclip_with_body())

      assert step.exit_reason == "success"
      assert step.output_dataclip.body == nil

      assert step.output_dataclip.wiped_at == Lightning.current_time()
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

  describe "get_input/1" do
    setup context do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      dataclip =
        case context.dataclip_type do
          :http_request ->
            insert(:http_request_dataclip)

          :kafka ->
            insert(
              :dataclip,
              body: %{"foo" => "bar"},
              request: %{"ts" => 1_720_607_114_132, "topic" => "baz_topic"},
              type: :kafka
            )

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

    @tag dataclip_type: :kafka
    test "returns headers and body for kafka datclip", %{run: run} do
      input =
        run
        |> Runs.get_input()
        |> Jason.decode!()

      expected = %{
        "data" => %{"foo" => "bar"},
        "request" => %{"ts" => 1_720_607_114_132, "topic" => "baz_topic"}
      }

      assert input == expected
    end
  end

  describe "get/2" do
    setup context do
      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow) |> with_snapshot()

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

    @tag dataclip_type: :http_request
    test "retrieves a run with a snapshot", %{run: run} do
      assert %{snapshot: %Lightning.Workflows.Snapshot{}} =
               Runs.get(run.id, include: [:snapshot])
    end
  end

  describe "get_for_worker/1" do
    setup do
      trigger =
        build(:trigger,
          type: :webhook,
          enabled: true
        )

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          project_credential: build(:project_credential)
        )

      %{triggers: [trigger]} =
        workflow =
        build(:workflow)
        |> with_trigger(trigger)
        |> with_job(job)
        |> with_edge({trigger, job}, condition_type: :always)
        |> insert()
        |> with_snapshot()

      dataclip = insert(:dataclip)

      %{trigger: trigger, workflow: workflow, dataclip: dataclip}
    end

    test "retrieves a run with a snapshot and credential", %{
      trigger: trigger,
      workflow: workflow,
      dataclip: dataclip
    } do
      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      run = Runs.get_for_worker(run.id)
      refute is_struct(run.snapshot, Ecto.Association.NotLoaded)

      assert run.snapshot.jobs
             |> List.first()
             |> Map.get(:credential)
    end

    test "builds a snapshot for runs that don't have one", %{
      workflow: workflow,
      dataclip: dataclip,
      trigger: trigger
    } do
      # While snapshots are being introduced, we need to ensure that
      # runs have a snapshot associated with them.
      # Here we intentionally create a run _without_ a snapshot.
      run =
        insert(:run,
          work_order:
            build(:workorder,
              workflow: workflow,
              dataclip: dataclip,
              trigger: trigger
            ),
          starting_trigger: trigger,
          dataclip: dataclip
        )

      run = Runs.get_for_worker(run.id)

      assert run.snapshot_id
      refute is_struct(run.snapshot, Ecto.Association.NotLoaded)
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
      current_time = ~U[2024-05-05 12:34:56.000000Z]
      Lightning.Stub.freeze_time(current_time)

      assert {:ok, %Run{started_at: started_at}} =
               Runs.start_run(run)

      assert started_at == Lightning.current_time()

      assert_received %Lightning.WorkOrders.Events.WorkOrderUpdated{
        work_order: %{id: ^workorder_id}
      }
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
        Runs.complete_run(run, %{state: "success"})

      assert {:state,
              {"cannot mark run success that has not been claimed by a worker",
               []}} in changeset.errors

      {:ok, run} =
        Repo.update(run |> Ecto.Changeset.change(state: :claimed))

      # TODO: test that the workorder has it's state updated
      current_time = ~U[2024-05-05 12:34:56.000000Z]
      Lightning.Stub.freeze_time(current_time)

      {:ok, run} = Runs.start_run(run)

      assert WorkOrders.get(run.work_order_id).state == :running

      Lightning.WorkOrders.subscribe(workflow.project_id)

      {:ok, run} = Runs.complete_run(run, %{state: "success"})

      assert run.state == :success
      assert run.finished_at == Lightning.current_time()

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
        Runs.complete_run(run, %{state: "lost", error_type: "Lost"})

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
        Runs.complete_run(run, %{state: "lost", error_type: "Lost"})

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
                    type: {:parameterized, {Ecto.Enum, _}},
                    validation: :inclusion,
                    enum: ~w(
                      available cancelled claimed crashed exception
                      failed killed lost started success
                    )
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

      assert {:message, {"can't be blank", []}} in changeset.errors

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

      current_time = ~U[2024-05-05 12:34:56Z]

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          claimed_at: current_time |> DateTime.add(-3600)
        )

      finished_step =
        insert(:step,
          runs: [run],
          finished_at: current_time,
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

    @tag :capture_log
    test "triggers an event to mark the lost run" do
      lost_run_event = [:lightning, :run, :lost]

      ref = :telemetry_test.attach_event_handlers(self(), [lost_run_event])

      worker_name = "my.worker.name"

      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      current_time = ~U[2024-05-05 12:34:56Z]

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          claimed_at: current_time |> DateTime.add(-3600),
          worker_name: worker_name
        )

      _finished_step =
        insert(:step,
          runs: [run],
          finished_at: current_time,
          exit_reason: "success"
        )

      _unfinished_step = insert(:step, runs: [run])

      Runs.mark_run_lost(run)

      assert_received {
        ^lost_run_event,
        ^ref,
        %{count: 1},
        %{}
      }
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

      current_time = ~U[2024-05-05 12:34:56Z]
      Lightning.Stub.freeze_time(current_time)

      :ok = Runs.wipe_dataclips(run)

      # dataclip body is cleared
      query = from(Invocation.Dataclip, select: [:wiped_at, :body, :request])

      updated_dataclip = Lightning.Repo.get(query, dataclip.id)

      assert updated_dataclip.wiped_at == current_time

      refute updated_dataclip.body
      refute updated_dataclip.request
    end

    test "emits a DataclipUpdated Event" do
      project = insert(:project)
      dataclip = insert(:http_request_dataclip, project: project)

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project)

      %{runs: [run]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      # subscribe to run events
      Runs.subscribe(run)

      :ok = Runs.wipe_dataclips(run)

      dataclip_id = dataclip.id

      assert_received %Lightning.Runs.Events.DataclipUpdated{
        dataclip: %{id: ^dataclip_id}
      }
    end
  end
end
