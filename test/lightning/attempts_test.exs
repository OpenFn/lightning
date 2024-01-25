defmodule Lightning.AttemptsTest do
  alias Lightning.Invocation
  use Lightning.DataCase
  import Lightning.Factories
  import Mock

  alias Lightning.WorkOrders
  alias Lightning.Attempt
  alias Lightning.Attempts

  describe "enqueue/1" do
    test "enqueues an attempt" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      attempt =
        build(:attempt,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      assert {:ok, queued_attempt} = Attempts.enqueue(attempt)

      assert queued_attempt.id == attempt.id
      assert queued_attempt.state == :available
    end
  end

  describe "claim/1" do
    test "claims an attempt from the queue" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      {:ok, %{attempts: [attempt]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      assert {:ok, [claimed]} = Attempts.claim()

      assert claimed.id == attempt.id
      assert claimed.state == :claimed

      assert {:ok, []} = Attempts.claim()
    end

    test "claims with demand" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      [attempt_1, attempt_2, attempt_3] =
        1..3
        |> Enum.map(fn _ ->
          {:ok, %{attempts: [attempt]}} =
            WorkOrders.create_for(trigger,
              workflow: workflow,
              dataclip: params_with_assocs(:dataclip)
            )

          attempt
        end)

      assert {:ok, [claimed_1, claimed_2]} = Attempts.claim(2)

      assert claimed_1.id == attempt_1.id
      assert claimed_1.state == :claimed
      assert claimed_2.id == attempt_2.id
      assert claimed_2.state == :claimed

      assert {:ok, [claimed_3]} = Attempts.claim(2)

      assert claimed_3.id == attempt_3.id
      assert claimed_3.state == :claimed
    end

    test "claims with demand for all immediate attempt" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      [second_last_attempt, last_attempt] =
        Enum.map(1..2, fn _i ->
          WorkOrders.create_for(trigger,
            workflow: workflow,
            dataclip: params_with_assocs(:dataclip)
          )
          |> then(fn {:ok, %{attempts: [attempt]}} -> attempt end)
        end)

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      attempts =
        Map.new(1..4, fn i ->
          build(:attempt,
            work_order: work_order,
            starting_trigger: trigger,
            dataclip: dataclip,
            priority: :immediate
          )
          |> Attempts.enqueue()
          |> then(fn {:ok, attempt} -> {i, attempt} end)
        end)

      assert {:ok, [claimed_1, claimed_2]} = Attempts.claim(2)

      assert claimed_1.id == attempts[1].id
      assert claimed_1.state == :claimed
      assert claimed_2.id == attempts[2].id
      assert claimed_2.state == :claimed

      assert {:ok, [claimed_3]} = Attempts.claim()

      assert claimed_3.id == attempts[3].id
      assert claimed_3.state == :claimed

      assert {:ok, [claimed_4, claimed_5]} = Attempts.claim(2)

      assert claimed_4.id in [attempts[4].id, second_last_attempt.id]
      assert claimed_4.state == :claimed

      assert claimed_5.id != claimed_4.id
      assert claimed_5.id in [attempts[4].id, second_last_attempt.id]
      assert claimed_5.state == :claimed

      assert {:ok, [claimed_6]} = Attempts.claim(2)

      assert claimed_6.id == last_attempt.id
      assert claimed_6.state == :claimed
    end
  end

  describe "dequeue/1" do
    test "removes an attempt from the queue" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      {:ok, %{attempts: [attempt]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      assert {:ok, dequeued} = Attempts.dequeue(attempt)

      refute dequeued |> Repo.reload()
    end
  end

  describe "start_step/1" do
    test "creates a new step for an attempt" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Attempts.start_step(%{
          "attempt_id" => attempt.id,
          "job_id" => Ecto.UUID.generate(),
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors
      refute {:attempt_id, {"does not exist", []}} in changeset.errors

      # both attempt_id and job_id doesn't exist
      {:error, changeset} =
        Attempts.start_step(%{
          "attempt_id" => Ecto.UUID.generate(),
          "job_id" => Ecto.UUID.generate(),
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors
      assert {:attempt_id, {"does not exist", []}} in changeset.errors

      Lightning.WorkOrders.subscribe(workflow.project_id)

      {:ok, step} =
        Attempts.start_step(%{
          "attempt_id" => attempt.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => _step_id = Ecto.UUID.generate()
        })

      assert step.started_at, "The step has been marked as started"

      assert Repo.get_by(Lightning.AttemptStep, step_id: step.id),
             "There is a corresponding AttemptStep linking it to the attempt"

      attempt_id = attempt.id

      assert_received %Lightning.WorkOrders.Events.AttemptUpdated{
        attempt: %{id: ^attempt_id}
      }
    end
  end

  describe "complete_step/1" do
    test "marks a step as finished" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      step =
        insert(:step, attempts: [attempt], job: job, input_dataclip: dataclip)

      {:ok, step} =
        Attempts.complete_step(%{
          step_id: step.id,
          reason: "success",
          output_dataclip: ~s({"foo": "bar"}),
          output_dataclip_id: Ecto.UUID.generate(),
          attempt_id: attempt.id,
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

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      step =
        insert(:step, attempts: [attempt], job: job, input_dataclip: dataclip)

      assert {:error, %Ecto.Changeset{}} =
               Attempts.complete_step(%{
                 step_id: step.id
               })
    end

    test "with an non-existant step returns an error changeset" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      assert {:error, %Ecto.Changeset{errors: [step_id: {"not found", []}]}} =
               Attempts.complete_step(%{
                 step_id: Ecto.UUID.generate(),
                 reason: "success",
                 output_dataclip: ~s({"foo": "bar"}),
                 output_dataclip_id: Ecto.UUID.generate(),
                 attempt_id: attempt.id,
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

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      %{attempt: attempt}
    end

    @tag dataclip_type: :step_result
    test "returns the body of a dataclip", %{attempt: attempt} do
      assert Attempts.get_input(attempt) == ~s({"i'm": ["a", "dataclip"]})
    end

    @tag dataclip_type: :http_request
    test "returns headers and body for http_request", %{attempt: attempt} do
      assert Attempts.get_input(attempt) ==
               ~s({"data": {"foo": "bar"}, "request": {"headers": {"content-type": "application/json"}}})
    end
  end

  describe "start_attempt/1" do
    setup do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        workorder =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, attempt} =
        Repo.update(attempt |> Ecto.Changeset.change(state: :claimed))

      Lightning.WorkOrders.subscribe(workflow.project_id)

      %{attempt: attempt, workorder_id: workorder.id}
    end

    test "marks an attempt as started",
         %{attempt: attempt, workorder_id: workorder_id} do
      assert {:ok, %Attempt{started_at: started_at}} =
               Attempts.start_attempt(attempt)

      assert DateTime.compare(started_at, DateTime.utc_now()) == :lt

      assert_received %Lightning.WorkOrders.Events.WorkOrderUpdated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "indicates if a response was unsuccessful", %{attempt: attempt} do
      with_mock(
        Lightning.Repo,
        transaction: fn _multi -> {:error, nil, %Ecto.Changeset{}, nil} end
      ) do
        assert Attempts.start_attempt(attempt) == {:error, %Ecto.Changeset{}}
      end
    end

    test "triggers a metric if starting the attempt was successful",
         %{attempt: attempt} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:domain, :attempt, :queue]]
        )

      {:ok,
       %Attempt{
         started_at: started_at,
         inserted_at: inserted_at
       }} =
        Attempts.start_attempt(attempt)

      delay = DateTime.diff(started_at, inserted_at, :millisecond)

      assert_received {
        [:domain, :attempt, :queue],
        ^ref,
        %{delay: ^delay},
        %{}
      }
    end

    test "does not trigger a metric if starting the attempt was unsuccessful",
         %{attempt: attempt} do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:domain, :attempt, :queue]]
        )

      with_mock(
        Lightning.Repo,
        transaction: fn _multi -> {:error, nil, nil, nil} end
      ) do
        Attempts.start_attempt(attempt)
      end

      refute_received {
        [:domain, :attempt, :queue],
        ^ref,
        %{delay: _delay},
        %{}
      }
    end
  end

  describe "complete_attempt/1" do
    test "marks an attempt as complete" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        workorder =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      # Make another attempt to ensure the updating doesn't include other
      # attempts.
      %{attempts: [_attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Attempts.complete_attempt(attempt, %{state: :success})

      assert {:state,
              {"cannot mark attempt success that has not been claimed by a worker",
               []}} in changeset.errors

      {:ok, attempt} =
        Repo.update(attempt |> Ecto.Changeset.change(state: :claimed))

      # TODO: test that the workorder has it's state updated

      {:ok, attempt} = Attempts.start_attempt(attempt)

      assert WorkOrders.get(attempt.work_order_id).state == :running

      Lightning.WorkOrders.subscribe(workflow.project_id)

      {:ok, attempt} = Attempts.complete_attempt(attempt, %{state: :success})

      assert attempt.state == :success
      assert DateTime.after?(DateTime.utc_now(), attempt.finished_at)

      workorder_id = workorder.id

      assert_received %Lightning.WorkOrders.Events.WorkOrderUpdated{
        work_order: %{id: ^workorder_id}
      }
    end

    test "blocks completion from :available if new state is :lost" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, attempt} =
        attempt
        |> Ecto.Changeset.change(state: :available)
        |> Repo.update()

      {:error, changeset} =
        Attempts.complete_attempt(attempt, %{state: :lost, error_type: "Lost"})

      assert changeset.errors == [
               state:
                 {"cannot mark attempt lost that has not been claimed by a worker",
                  []}
             ]
    end

    test "allows completion from :claimed if new state is :lost" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, attempt} =
        attempt
        |> Ecto.Changeset.change(state: :claimed)
        |> Repo.update()

      {:ok, attempt} =
        Attempts.complete_attempt(attempt, %{state: :lost, error_type: "Lost"})

      assert attempt.state == :lost
    end

    test "returns error if state is not present" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, attempt} =
        attempt
        |> Ecto.Changeset.change(state: :started)
        |> Repo.update()

      {:error, changeset} =
        Attempts.complete_attempt(attempt, %{})

      assert changeset.errors == [
               state: {"can't be blank", [validation: :required]}
             ]
    end

    test "returns error if state is not identifiable" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, attempt} =
        attempt
        |> Ecto.Changeset.change(state: :started)
        |> Repo.update()

      {:error, changeset} =
        Attempts.complete_attempt(attempt, %{state: "some_unknown_state"})

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

  describe "append_attempt_log/3" do
    test "adds a log line to an attempt" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Attempts.append_attempt_log(attempt, %{source: "fooo-ooooo"})

      assert {:source,
              {"should be at most %{count} character(s)",
               [count: 8, validation: :length, kind: :max, type: :string]}} in changeset.errors

      assert {:message, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:timestamp, {"can't be blank", [validation: :required]}} in changeset.errors

      {:error, changeset} =
        Attempts.append_attempt_log(attempt, %{
          step_id: Ecto.UUID.generate(),
          message: "I'm a log line",
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert {:step_id, {"must be associated with the attempt", []}} in changeset.errors

      {:ok, _log_line} =
        Attempts.append_attempt_log(attempt, %{
          message: "I'm a log line",
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      step =
        insert(:step, attempts: [attempt], job: job, input_dataclip: dataclip)

      {:ok, log_line} =
        Attempts.append_attempt_log(attempt, %{
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

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, log_line} =
        Attempts.append_attempt_log(attempt, %{
          message: [%{"foo" => "bar"}, "hello there"],
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert log_line.message == ~s<{"foo":"bar"} hello there>

      {:ok, log_line} =
        Attempts.append_attempt_log(attempt, %{
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

      attempt =
        insert(:attempt,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      finished_step =
        insert(:step,
          attempts: [attempt],
          finished_at: DateTime.utc_now(),
          exit_reason: "success"
        )

      unfinished_step = insert(:step, attempts: [attempt])

      Attempts.mark_attempt_lost(attempt)

      reloaded_finished_step = Repo.get(Invocation.Step, finished_step.id)
      reloaded_unfinished_step = Repo.get(Invocation.Step, unfinished_step.id)

      assert reloaded_finished_step.exit_reason == "success"
      assert reloaded_unfinished_step.exit_reason == "lost"

      assert reloaded_unfinished_step.finished_at != nil
    end
  end

  describe "wipe_dataclip_body/1" do
    test "clears the dataclip body and request fields" do
      project = insert(:project)
      dataclip = insert(:http_request_dataclip, project: project)

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      assert dataclip.body
      assert dataclip.request
      refute dataclip.wiped_at

      :ok = Attempts.wipe_dataclip_body(attempt)

      # dataclip body is cleared
      updated_dataclip = Lightning.Invocation.get_dataclip_details!(dataclip.id)
      assert updated_dataclip.wiped_at
      refute updated_dataclip.body
      refute updated_dataclip.request
    end
  end
end
