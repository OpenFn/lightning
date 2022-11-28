defmodule Lightning.InvocationTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation
  alias Lightning.Repo
  import Lightning.InvocationFixtures
  import Lightning.ProjectsFixtures
  import Lightning.JobsFixtures

  describe "dataclips" do
    alias Lightning.Invocation.Dataclip

    @invalid_attrs %{body: nil, type: nil}

    test "list_dataclips/0 returns all dataclips" do
      dataclip = dataclip_fixture()
      assert Invocation.list_dataclips() == [dataclip]
    end

    test "list_dataclips/1 returns dataclips for project, desc by inserted_at" do
      project = project_fixture()

      old_dataclip =
        dataclip_fixture(project_id: project.id)
        |> shift_inserted_at!(days: -2)

      new_dataclip =
        dataclip_fixture(project_id: project.id)
        |> shift_inserted_at!(days: -1)

      assert Invocation.list_dataclips(project)
             |> Enum.map(fn x -> x.id end) ==
               [new_dataclip.id, old_dataclip.id]
    end

    test "get_dataclip!/1 returns the dataclip with given id" do
      dataclip = dataclip_fixture()
      assert Invocation.get_dataclip!(dataclip.id) == dataclip

      assert_raise Ecto.NoResultsError, fn ->
        Invocation.get_dataclip!(Ecto.UUID.generate())
      end
    end

    test "get_dataclip/1 returns the dataclip with given id" do
      dataclip = dataclip_fixture()
      assert Invocation.get_dataclip(dataclip.id) == dataclip
      assert Invocation.get_dataclip(Ecto.UUID.generate()) == nil

      run = run_fixture(input_dataclip_id: dataclip.id)

      assert Invocation.get_dataclip(run) == dataclip
    end

    test "create_dataclip/1 with valid data creates a dataclip" do
      project = project_fixture()
      valid_attrs = %{body: %{}, project_id: project.id, type: :http_request}

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.create_dataclip(valid_attrs)

      assert dataclip.body == %{}
      assert dataclip.type == :http_request
    end

    test "create_dataclip/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Invocation.create_dataclip(@invalid_attrs)
    end

    test "update_dataclip/2 with valid data updates the dataclip" do
      dataclip = dataclip_fixture()
      update_attrs = %{body: %{}, type: :global}

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.update_dataclip(dataclip, update_attrs)

      assert dataclip.body == %{}
      assert dataclip.type == :global
    end

    test "update_dataclip/2 with invalid data returns error changeset" do
      dataclip = dataclip_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_dataclip(dataclip, @invalid_attrs)

      assert dataclip == Invocation.get_dataclip!(dataclip.id)
    end

    test "delete_dataclip/1 sets the body to nil" do
      dataclip = dataclip_fixture()
      assert {:ok, %Dataclip{}} = Invocation.delete_dataclip(dataclip)

      assert %{body: nil} = Invocation.get_dataclip!(dataclip.id)
    end

    test "change_dataclip/1 returns a dataclip changeset" do
      dataclip = dataclip_fixture()
      assert %Ecto.Changeset{} = Invocation.change_dataclip(dataclip)
    end
  end

  describe "runs" do
    alias Lightning.Invocation.Run

    import Lightning.InvocationFixtures
    import Lightning.ProjectsFixtures
    import Lightning.WorkflowsFixtures

    @invalid_attrs %{job_id: nil}
    @valid_attrs %{
      exit_code: 42,
      finished_at: ~U[2022-02-02 11:49:00.000000Z],
      log: [],
      started_at: ~U[2022-02-02 11:49:00.000000Z]
    }

    test "list_runs/0 returns all runs" do
      run = run_fixture()
      assert Invocation.list_runs() == [run]
    end

    test "list_runs_for_project/2 returns runs ordered by inserted at desc" do
      workflow = workflow_fixture() |> Repo.preload(:project)
      job_one = job_fixture(workflow_id: workflow.id)
      job_two = job_fixture(workflow_id: workflow.id)

      first_run =
        run_fixture(job_id: job_one.id)
        |> shift_inserted_at!(days: -1)
        |> Repo.preload(:job)

      second_run =
        run_fixture(job_id: job_two.id)
        |> Repo.preload(:job)

      third_run =
        run_fixture(job_id: job_one.id)
        |> Repo.preload(:job)

      assert Invocation.list_runs_for_project(workflow.project).entries == [
               third_run,
               second_run,
               first_run
             ]
    end

    test "get_run!/1 returns the run with given id" do
      run = run_fixture()
      assert Invocation.get_run!(run.id) == run
    end

    test "create_run/1 with valid data creates a run" do
      project = project_fixture()
      dataclip = dataclip_fixture(project_id: project.id)
      job = job_fixture(workflow_id: workflow_fixture(project_id: project.id).id)

      assert {:ok, %Run{} = run} =
               Invocation.create_run(
                 Map.merge(@valid_attrs, %{
                   job_id: job.id,
                   input_dataclip_id: dataclip.id
                 })
               )

      assert run.exit_code == 42
      assert run.finished_at == ~U[2022-02-02 11:49:00.000000Z]
      assert run.log == []
      assert run.started_at == ~U[2022-02-02 11:49:00.000000Z]
    end

    test "create_run/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Invocation.create_run(@invalid_attrs)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Map.merge(@valid_attrs, %{event_id: Ecto.UUID.generate()})
               |> Invocation.create_run()

      assert event_id:
               {
                 "does not exist",
                 [constraint: :foreign, constraint_name: "runs_event_id_fkey"]
               } in errors
    end

    test "update_run/2 with valid data updates the run" do
      run = run_fixture()

      update_attrs = %{
        exit_code: 43,
        finished_at: ~U[2022-02-03 11:49:00.000000Z],
        log: [],
        started_at: ~U[2022-02-03 11:49:00.000000Z]
      }

      assert {:ok, %Run{} = run} = Invocation.update_run(run, update_attrs)
      assert run.exit_code == 43
      assert run.finished_at == ~U[2022-02-03 11:49:00.000000Z]
      assert run.log == []
      assert run.started_at == ~U[2022-02-03 11:49:00.000000Z]
    end

    test "update_run/2 with invalid data returns error changeset" do
      run = run_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_run(run, @invalid_attrs)

      assert run == Invocation.get_run!(run.id)
    end

    test "delete_run/1 deletes the run" do
      run = run_fixture()
      assert {:ok, %Run{}} = Invocation.delete_run(run)
      assert_raise Ecto.NoResultsError, fn -> Invocation.get_run!(run.id) end
    end

    test "change_run/1 returns a run changeset" do
      run = run_fixture()
      assert %Ecto.Changeset{} = Invocation.change_run(run)
    end

    test "list_work_orders_for_project/1 returns work orders ordered by last run finished at desc, with nulls first" do
      job = workflow_job_fixture(workflow_name: "chw-help")
      job_2 = job_fixture(workflow_id: job.workflow_id)
      reason = reason_fixture(trigger_id: job.trigger.id)
      workflow = job.workflow

      wo_one = work_order_fixture(workflow_id: workflow.id)
      wo_four = work_order_fixture(workflow_id: workflow.id)
      wo_two = work_order_fixture(workflow_id: workflow.id)
      wo_three = work_order_fixture(workflow_id: workflow.id)

      dataclip = dataclip_fixture()

      now = Timex.now()

      %{runs: [_run_one, run_two]} =
        Lightning.Attempt.new(%{
          work_order_id: wo_one.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job.id,
              started_at: now |> Timex.shift(seconds: -50),
              finished_at: now |> Timex.shift(seconds: -40),
              exit_code: 0,
              input_dataclip_id: dataclip.id
            },
            %{
              job_id: job_2.id,
              started_at: now |> Timex.shift(seconds: -41),
              finished_at: now |> Timex.shift(seconds: -43),
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      %{runs: [run_three]} =
        Lightning.Attempt.new(%{
          work_order_id: wo_two.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job.id,
              started_at: now |> Timex.shift(seconds: -40),
              finished_at: now |> Timex.shift(seconds: -30),
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      %{runs: [run_four]} =
        Lightning.Attempt.new(%{
          work_order_id: wo_three.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job.id,
              started_at: now |> Timex.shift(seconds: -30),
              finished_at: now |> Timex.shift(seconds: -20),
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      %{runs: [run_five]} =
        Lightning.Attempt.new(%{
          work_order_id: wo_four.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job.id,
              started_at: now |> Timex.shift(seconds: -20),
              finished_at: nil,
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      simplified_result =
        Invocation.list_work_orders_for_project(%Lightning.Projects.Project{
          id: workflow.project_id
        }).entries()
        |> Enum.map(fn %{work_order: wo} ->
          %{
            id: wo.id,
            last_run_finished_at:
              Enum.at(wo.attempts, 0)
              |> Map.get(:runs)
              |> Enum.at(0)
              |> Map.get(:finished_at)
          }
        end)

      expected_order = [
        %{id: wo_four.id, last_run_finished_at: run_five.finished_at},
        %{id: wo_three.id, last_run_finished_at: run_four.finished_at},
        %{id: wo_two.id, last_run_finished_at: run_three.finished_at},
        %{id: wo_one.id, last_run_finished_at: run_two.finished_at}
      ]

      assert expected_order == simplified_result
    end

    test "list_work_orders_for_project/1 returns runs ordered by desc finished_at" do
      job_one = workflow_job_fixture(workflow_name: "chw-help")
      # job_two = workflow_job_fixture(workflow_id: job_one.workflow_id)

      workflow = job_one.workflow
      work_order = work_order_fixture(workflow_id: workflow.id)
      reason = reason_fixture(trigger_id: job_one.trigger.id)

      dataclip = dataclip_fixture()

      ### when inserting in this order

      # work_oder
      #   -- attempt_one
      #       -- run_one
      #       -- run_two
      #   -- attempt_two
      #       -- run_three
      #       -- run_four

      ### we expect

      # work_oder
      #   -- attempt_two
      #       -- run_four
      #       -- run_three
      #   -- attempt_one
      #       -- run_two
      #       -- run_one

      {:ok, attempt_one} =
        Lightning.AttemptService.create_attempt(
          work_order,
          job_one,
          reason
        )

      run_one = Enum.at(attempt_one.runs, 0)

      Invocation.update_run(run_one, %{
        exit_code: 0,
        started_at: ~U[2022-10-27 00:00:00.000000Z],
        finished_at: ~U[2022-10-27 01:00:00.000000Z]
      })

      Lightning.AttemptService.append(
        attempt_one,
        # run_two
        Run.changeset(%Run{}, %{
          project_id: workflow.project_id,
          job_id: job_one.id,
          input_dataclip_id: dataclip.id,
          exit_code: 0,
          started_at: ~U[2022-10-27 01:10:00.000000Z],
          finished_at: ~U[2022-10-27 02:00:00.000000Z]
        })
      )

      # ---------------------------------------------------------

      {:ok, attempt_two} =
        Lightning.AttemptService.create_attempt(
          work_order,
          job_one,
          reason
        )

      run_three = Enum.at(attempt_two.runs, 0)

      Invocation.update_run(run_three, %{
        exit_code: 0,
        started_at: ~U[2022-10-27 03:00:00.000000Z],
        finished_at: ~U[2022-10-27 04:00:00.000000Z]
      })

      {:ok, %{run: run_four} = _attempt_run} =
        Lightning.AttemptService.append(
          attempt_two,
          # run_four
          Run.changeset(%Run{}, %{
            project_id: workflow.project_id,
            job_id: job_one.id,
            input_dataclip_id: dataclip.id,
            exit_code: 0,
            started_at: ~U[2022-10-27 05:10:00.000000Z],
            finished_at: ~U[2022-10-27 06:00:00.000000Z]
          })
        )

      [%{work_order: actual_wo} | _] =
        Invocation.list_work_orders_for_project(%Lightning.Projects.Project{
          id: workflow.project_id
        }).entries()

      # last created attempt should be first in work_order.attempts list

      actual_last_attempt = Enum.at(actual_wo.attempts, 0)

      assert actual_last_attempt.id == attempt_two.id

      # last created run should be first in attempt.runs list

      actual_last_run = List.last(actual_last_attempt.runs)

      assert actual_last_run.id == run_four.id

      # make run_three finish later

      {:ok, run_three} =
        Invocation.update_run(run_three, %{
          finished_at: ~U[2022-10-27 15:00:00.000000Z]
        })

      [%{work_order: actual_wo} | _] =
        Invocation.list_work_orders_for_project(%Lightning.Projects.Project{
          id: workflow.project_id
        }).entries()

      actual_last_attempt = Enum.at(actual_wo.attempts, 0)

      assert actual_last_attempt.id == attempt_two.id

      actual_last_run = List.last(actual_last_attempt.runs)

      assert actual_last_run.id == run_three.id
    end
  end

  # defp shift_date(date, shift_attrs) do
  #   date
  #   |> Timex.shift(shift_attrs)
  #   |> Timex.to_naive_datetime()
  # end
end
