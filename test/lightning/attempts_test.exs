defmodule Lightning.AttemptsTest do
  alias Lightning.Invocation
  use Lightning.DataCase, async: true
  import Lightning.Factories

  alias Lightning.WorkOrders
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

  describe "start_run/1" do
    test "creates a new run for an attempt" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} =
        Attempts.start_run(%{
          "attempt_id" => attempt.id,
          "job_id" => Ecto.UUID.generate(),
          "input_dataclip_id" => dataclip.id,
          "run_id" => _run_id = Ecto.UUID.generate()
        })

      assert {:job_id, {"does not exist", []}} in changeset.errors

      {:ok, run} =
        Attempts.start_run(%{
          "attempt_id" => attempt.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "run_id" => _run_id = Ecto.UUID.generate()
        })

      assert run.started_at, "The run has been marked as started"

      assert Repo.get_by(Lightning.AttemptRun, run_id: run.id),
             "There is a corresponding AttemptRun linking it to the attempt"
    end
  end

  describe "complete_run/1" do
    test "marks a run as finished" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      run = insert(:run, attempts: [attempt], job: job, input_dataclip: dataclip)

      {:ok, run} =
        Attempts.complete_run(%{
          run_id: run.id,
          reason: "success",
          output_dataclip: ~s({"foo": "bar"}),
          output_dataclip_id: Ecto.UUID.generate(),
          attempt_id: attempt.id,
          project_id: workflow.project_id
        })

      run =
        run
        |> Repo.preload(output_dataclip: Invocation.Query.dataclip_with_body())

      assert run.exit_reason == "success"
      assert run.output_dataclip.body == %{"foo" => "bar"}
    end

    test "with invalid data returns error changeset" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      run = insert(:run, attempts: [attempt], job: job, input_dataclip: dataclip)

      assert {:error, %Ecto.Changeset{}} =
               Attempts.complete_run(%{
                 run_id: run.id
               })
    end
  end

  describe "start_attempt/1" do
    test "marks a run as started" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, attempt} =
        Repo.update(attempt |> Ecto.Changeset.change(state: :claimed))

      {:ok, attempt} = Attempts.start_attempt(attempt)

      assert attempt.started_at <= DateTime.utc_now()
    end
  end

  describe "complete_attempt/1" do
    test "marks an attempt as complete" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      # Make another attempt to ensure the updating doesn't include other
      # attempts.
      %{attempts: [_attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:error, changeset} = Attempts.complete_attempt(attempt, "success")

      assert {:state, {"cannot complete attempt that is not started", []}} in changeset.errors

      {:ok, attempt} =
        Repo.update(attempt |> Ecto.Changeset.change(state: :claimed))

      # TODO: test that the workorder has it's state updated

      {:ok, attempt} = Attempts.start_attempt(attempt)

      assert WorkOrders.get(attempt.work_order_id).state == :running

      {:ok, attempt} = Attempts.complete_attempt(attempt, "success")

      assert attempt.state == :success
      assert DateTime.utc_now() >= attempt.finished_at
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
        Attempts.complete_attempt(attempt, nil)

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
        Attempts.complete_attempt(attempt, "some_unknown_state")

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

  describe "append_attempt_log/1" do
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
          run_id: Ecto.UUID.generate(),
          message: "I'm a log line",
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert {:run_id, {"must be associated with the attempt", []}} in changeset.errors

      {:ok, _log_line} =
        Attempts.append_attempt_log(attempt, %{
          message: "I'm a log line",
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      run = insert(:run, attempts: [attempt], job: job, input_dataclip: dataclip)

      {:ok, log_line} =
        Attempts.append_attempt_log(attempt, %{
          message: "I'm another log line",
          run_id: run.id,
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      log_line = log_line |> Repo.reload!() |> Repo.preload(:run)

      assert log_line.run.id == run.id
    end

    test "adding json objects as messages" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger], jobs: [_job]} = workflow = insert(:simple_workflow)

      %{attempts: [attempt]} =
        work_order_for(trigger, workflow: workflow, dataclip: dataclip)
        |> insert()

      {:ok, log_line} =
        Attempts.append_attempt_log(attempt, %{
          message: [%{"foo" => "bar"}],
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert log_line.message == [%{"foo" => "bar"}] |> Jason.encode!()

      {:ok, log_line} =
        Attempts.append_attempt_log(attempt, %{
          message: %{"foo" => "bar"},
          timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
        })

      assert log_line.message == %{"foo" => "bar"} |> Jason.encode!()
    end
  end
end
