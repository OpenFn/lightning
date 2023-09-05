defmodule Lightning.InvocationTest do
  use Lightning.DataCase, async: true

  alias Lightning.Pipeline
  alias Lightning.Workorders.SearchParams
  alias Lightning.Invocation
  alias Lightning.Invocation.Run
  alias Lightning.Repo
  import Lightning.Factories

  describe "dataclips" do
    alias Lightning.Invocation.Dataclip

    @invalid_attrs %{body: nil, type: nil}

    test "list_dataclips/0 returns all dataclips" do
      dataclip = insert(:dataclip)

      assert Invocation.list_dataclips()
             |> Enum.map(fn dataclip -> dataclip.id end) == [dataclip.id]
    end

    test "list_dataclips/1 returns dataclips for project, desc by inserted_at" do
      project = insert(:project)

      old_dataclip =
        insert(:dataclip, project: project)
        |> shift_inserted_at!(days: -2)

      new_dataclip =
        insert(:dataclip, project: project)
        |> shift_inserted_at!(days: -1)

      assert Invocation.list_dataclips(project)
             |> Enum.map(fn x -> x.id end) ==
               [new_dataclip.id, old_dataclip.id]
    end

    test "get_dataclip!/1 returns the dataclip with given id" do
      dataclip = insert(:dataclip)

      assert Invocation.get_dataclip!(dataclip.id) |> Repo.preload(:project) ==
               dataclip

      assert_raise Ecto.NoResultsError, fn ->
        Invocation.get_dataclip!(Ecto.UUID.generate())
      end
    end

    test "get_dataclip/1 returns the dataclip with given id" do
      dataclip = insert(:dataclip)

      assert Invocation.get_dataclip(dataclip.id) |> Repo.preload(:project) ==
               dataclip

      assert Invocation.get_dataclip(Ecto.UUID.generate()) == nil

      run = insert(:run, input_dataclip: dataclip)

      assert Invocation.get_dataclip(run) |> Repo.preload(:project) ==
               dataclip
    end

    test "create_dataclip/1 with valid data creates a dataclip" do
      project = insert(:project)
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
      dataclip = insert(:dataclip)
      update_attrs = %{body: %{}, type: :global}

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.update_dataclip(dataclip, update_attrs)

      assert dataclip.body == %{}
      assert dataclip.type == :global
    end

    test "update_dataclip/2 with invalid data returns error changeset" do
      dataclip = insert(:dataclip)

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_dataclip(dataclip, @invalid_attrs)

      assert dataclip ==
               Invocation.get_dataclip!(dataclip.id) |> Repo.preload(:project)
    end

    test "delete_dataclip/1 sets the body to nil" do
      dataclip = insert(:dataclip)
      assert {:ok, %Dataclip{}} = Invocation.delete_dataclip(dataclip)

      assert %{body: nil} = Invocation.get_dataclip!(dataclip.id)
    end

    test "change_dataclip/1 returns a dataclip changeset" do
      dataclip = insert(:dataclip)
      assert %Ecto.Changeset{} = Invocation.change_dataclip(dataclip)
    end
  end

  describe "runs" do
    @invalid_attrs %{job_id: nil}
    @valid_attrs %{
      exit_code: 42,
      finished_at: ~U[2022-02-02 11:49:00.000000Z],
      log: [],
      started_at: ~U[2022-02-02 11:49:00.000000Z]
    }

    test "list_runs/0 returns all runs" do
      run = insert(:run)
      assert Invocation.list_runs() |> Enum.map(fn r -> r.id end) == [run.id]
    end

    test "list_runs_for_project/2 returns runs ordered by inserted at desc" do
      workflow = insert(:workflow) |> Repo.preload(:project)
      job_one = insert(:job, workflow: workflow)
      job_two = insert(:job, workflow: workflow)

      first_run =
        insert(:run, job: job_one)
        |> shift_inserted_at!(days: -1)
        |> Repo.preload(:job)

      second_run =
        insert(:run, job: job_two)
        |> Repo.preload(:job)

      third_run =
        insert(:run, job: job_one)
        |> Repo.preload(:job)

      assert Invocation.list_runs_for_project(workflow.project).entries
             |> Enum.map(fn r -> r.id end) == [
               third_run.id,
               second_run.id,
               first_run.id
             ]
    end

    test "get_run!/1 returns the run with given id" do
      run = insert(:run)

      actual_run = Invocation.get_run!(run.id)

      assert actual_run.id == run.id
      assert actual_run.input_dataclip_id == run.input_dataclip_id
      assert actual_run.job_id == run.job_id
    end

    test "create_run/1 with valid data creates a run" do
      project = insert(:project)
      dataclip = insert(:dataclip, project: project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      assert {:ok, %Run{} = run} =
               Invocation.create_run(
                 Map.merge(@valid_attrs, %{
                   job_id: job.id,
                   input_dataclip_id: dataclip.id
                 })
               )

      assert run.exit_code == 42
      assert run |> Pipeline.logs_for_run() == []
      assert run.finished_at == ~U[2022-02-02 11:49:00.000000Z]
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

    test "create_log_line/2 create log lines for a given run" do
      run = insert(:run)
      Invocation.create_log_line(run, "log")

      run_logs = Invocation.get_run!(run.id) |> Pipeline.logs_for_run()

      assert length(run_logs) == 1
      assert [%{body: "log"}] = run_logs
    end

    test "create_log_line/2 transform logs with nil body to empty string" do
      run = insert(:run)
      Invocation.create_log_line(run, nil)

      run_logs = Invocation.get_run!(run.id) |> Pipeline.logs_for_run()

      assert length(run_logs) == 1
      assert [%{body: ""}] = run_logs
    end

    test "update_run/2 with valid data updates the run" do
      run = insert(:run) |> Repo.preload(:log_lines)

      update_attrs = %{
        exit_code: 43,
        finished_at: ~U[2022-02-03 11:49:00.000000Z],
        log_lines: [],
        started_at: ~U[2022-02-03 11:49:00.000000Z]
      }

      assert {:ok, %Run{} = run} = Invocation.update_run(run, update_attrs)
      assert run.exit_code == 43
      assert run.finished_at == ~U[2022-02-03 11:49:00.000000Z]
      assert Pipeline.logs_for_run(run) == []
      assert run.started_at == ~U[2022-02-03 11:49:00.000000Z]
    end

    test "update_run/2 with invalid data returns error changeset" do
      run = insert(:run)

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_run(run, @invalid_attrs)
    end

    test "delete_run/1 deletes the run" do
      run = insert(:run)
      assert {:ok, %Run{}} = Invocation.delete_run(run)
      assert_raise Ecto.NoResultsError, fn -> Invocation.get_run!(run.id) end
    end

    test "change_run/1 returns a run changeset" do
      run = insert(:run)
      assert %Ecto.Changeset{} = Invocation.change_run(run)
    end

    test "list_work_orders_for_project/1 returns workorders ordered by last run finished at desc, with nulls first" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow)

      dataclip = insert(:dataclip)

      reason =
        insert(:reason, type: :webhook, dataclip: dataclip, trigger: trigger)

      wo_one = insert(:workorder, reason: reason, workflow: workflow)
      wo_four = insert(:workorder, reason: reason, workflow: workflow)
      wo_two = insert(:workorder, reason: reason, workflow: workflow)
      wo_three = insert(:workorder, reason: reason, workflow: workflow)

      now = Timex.now()

      %{runs: [run_one]} =
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
            }
          ]
        })
        |> Lightning.Repo.insert!()

      %{runs: [run_two]} =
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

      %{runs: [run_three]} =
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

      %{runs: [run_four]} =
        Lightning.Attempt.new(%{
          work_order_id: wo_four.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job.id,
              started_at: now |> Timex.shift(seconds: -25),
              finished_at: nil,
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      simplified_result =
        Invocation.search_workorders(
          %Lightning.Projects.Project{
            id: workflow.project_id
          },
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        ).entries()

      expected_order = [
        %{
          id: wo_four.id,
          last_finished_at: run_four.finished_at,
          workflow_id: workflow.id
        },
        %{
          id: wo_three.id,
          last_finished_at: run_three.finished_at,
          workflow_id: workflow.id
        },
        %{
          id: wo_two.id,
          last_finished_at: run_two.finished_at,
          workflow_id: workflow.id
        },
        %{
          id: wo_one.id,
          last_finished_at: run_one.finished_at,
          workflow_id: workflow.id
        }
      ]

      assert expected_order == simplified_result
    end

    test "list_work_orders_for_project/1 returns runs ordered by desc finished_at" do
      project = insert(:project)
      workflow = insert(:workflow, name: "chw-help", project: project)
      job_one = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow)
      dataclip = insert(:dataclip)

      reason =
        insert(:reason, type: :webhook, dataclip: dataclip, trigger: trigger)

      work_order = insert(:workorder, reason: reason, workflow: workflow)

      ### when inserting in this order

      # work_order
      #   -- attempt_one
      #       -- run_one
      #       -- run_two
      #   -- attempt_two
      #       -- run_three
      #       -- run_four

      ### we expect

      # work_order
      #   -- attempt_two
      #       -- run_four
      #       -- run_three
      #   -- attempt_one
      #       -- run_two
      #       -- run_one

      %{runs: [_run_one, _run_two]} =
        Lightning.Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_one.id,
              input_dataclip_id: dataclip.id,
              exit_code: 0,
              started_at: ~U[2022-10-27 00:00:00.000000Z],
              finished_at: ~U[2022-10-27 01:00:00.000000Z]
            },
            %{
              job_id: job_one.id,
              input_dataclip_id: dataclip.id,
              exit_code: 0,
              started_at: ~U[2022-10-27 01:10:00.000000Z],
              finished_at: ~U[2022-10-27 02:00:00.000000Z]
            }
          ]
        })
        |> Repo.insert!()

      # ---------------------------------------------------------

      %{runs: [run_three, run_four]} =
        attempt_two =
        Lightning.Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_one.id,
              started_at: ~U[2022-10-27 03:00:00.000000Z],
              finished_at: ~U[2022-10-27 04:00:00.000000Z],
              exit_code: 0,
              input_dataclip_id: dataclip.id
            },
            %{
              job_id: job_one.id,
              started_at: ~U[2022-10-27 05:10:00.000000Z],
              finished_at: ~U[2022-10-27 06:00:00.000000Z],
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Repo.insert!()

      [%{id: id} | _] =
        Invocation.search_workorders(
          %Lightning.Projects.Project{
            id: workflow.project_id
          },
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "success" => "true",
            "timeout" => "true"
          })
        ).entries()

      [actual_wo] =
        Invocation.get_workorders_by_ids([id])
        |> Invocation.with_attempts()
        |> Lightning.Repo.all()

      # last created attempt should be first in work_order.attempts list

      actual_last_attempt = List.first(actual_wo.attempts)

      assert actual_last_attempt.id == attempt_two.id

      # last created run should be first in attempt.runs list

      actual_last_run = List.last(actual_last_attempt.runs)

      assert actual_last_run.id == run_four.id

      # make run_three finish later

      {:ok, run_three} =
        Invocation.update_run(run_three, %{
          finished_at: ~U[2022-10-27 15:00:00.000000Z]
        })

      [%{id: id} | _] =
        Invocation.search_workorders(
          %Lightning.Projects.Project{
            id: workflow.project_id
          },
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        ).entries()

      [actual_wo] =
        Invocation.get_workorders_by_ids([id])
        |> Invocation.with_attempts()
        |> Lightning.Repo.all()

      actual_last_attempt = List.first(actual_wo.attempts)

      assert actual_last_attempt.id == attempt_two.id

      actual_last_run = List.last(actual_last_attempt.runs)

      assert actual_last_run.id == run_three.id
    end

    test "list_work_orders_for_project/3 returns paginated workorders" do
      project = insert(:project)
      now = Timex.now()

      workflow = insert(:workflow, name: "chw-help", project: project)
      job1 = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow)

      Enum.each(1..10, fn index ->
        create_work_order(project, job1, trigger, now, 10 * index)
      end)

      wos =
        Invocation.search_workorders(
          %Lightning.Projects.Project{
            id: project.id
          },
          SearchParams.new(%{
            "success" => true,
            "pending" => true,
            "crash" => true,
            "failure" => true,
            "timeout" => true
          }),
          %{"page" => 1, "page_size" => 3}
        ).entries()

      assert length(wos) == 3
    end

    test "list_work_orders_for_project/3 returns paginated workorders with ordering" do
      #  we set a page size of 3

      # from now we set
      # 3 work_orders of workflow 1
      # 3 work_orders of workflow 2
      # 3 work_orders of workflow 3 (most recents)

      # all 15 workorders are executed one after another in asc order of finished_at

      # we expect to have in page 1, only workorders of workflow-3 correctly ordered

      # we expect to have in page 2, only workorders of workflow-2 correctly ordered

      # we expect to have in page 3, only workorders of workflow-1 correctly ordered

      project = insert(:project)
      workflow = insert(:workflow, name: "workflow-1", project: project)
      job1 = insert(:job, workflow: workflow)
      trigger1 = insert(:trigger, workflow: workflow)

      now = Timex.now()

      %{work_order: wf1_wo1, run: wf1_run1} =
        create_work_order(project, job1, trigger1, now, 10)

      %{work_order: wf1_wo2, run: wf1_run2} =
        create_work_order(project, job1, trigger1, now, 20)

      %{work_order: wf1_wo3, run: wf1_run3} =
        create_work_order(project, job1, trigger1, now, 30)

      workflow = insert(:workflow, name: "workflow-2", project: project)
      job2 = insert(:job, workflow: workflow)
      trigger2 = insert(:trigger, workflow: workflow)

      %{work_order: wf2_wo1, run: wf2_run1} =
        create_work_order(project, job2, trigger2, now, 40)

      %{work_order: wf2_wo2, run: wf2_run2} =
        create_work_order(project, job2, trigger2, now, 50)

      %{work_order: wf2_wo3, run: wf2_run3} =
        create_work_order(project, job2, trigger2, now, 60)

      workflow = insert(:workflow, name: "workflow-3", project: project)
      job3 = insert(:job, workflow: workflow)
      trigger3 = insert(:trigger, workflow: workflow)

      %{work_order: wf3_wo1, run: wf3_run1} =
        create_work_order(project, job3, trigger3, now, 70)

      %{work_order: wf3_wo2, run: wf3_run2} =
        create_work_order(project, job3, trigger3, now, 80)

      %{work_order: wf3_wo3, run: wf3_run3} =
        create_work_order(project, job3, trigger3, now, 90)

      ### PAGE 1 -----------------------------------------------------------------------

      page_one_result =
        get_simplified_page(
          project,
          %{"page" => 1, "page_size" => 3},
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        )

      # all work_orders in page_one are ordered by finished_at

      expected_order = [
        %{
          id: wf3_wo3.id,
          last_finished_at: wf3_run3.finished_at,
          workflow_id: job3.workflow_id
        },
        %{
          id: wf3_wo2.id,
          last_finished_at: wf3_run2.finished_at,
          workflow_id: job3.workflow_id
        },
        %{
          id: wf3_wo1.id,
          last_finished_at: wf3_run1.finished_at,
          workflow_id: job3.workflow_id
        }
      ]

      assert expected_order == page_one_result

      ### PAGE 2 -----------------------------------------------------------------------

      page_two_result =
        get_simplified_page(
          project,
          %{"page" => 2, "page_size" => 3},
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        )

      # all work_orders in page_two are ordered by finished_at
      expected_order = [
        %{
          id: wf2_wo3.id,
          last_finished_at: wf2_run3.finished_at,
          workflow_id: job2.workflow_id
        },
        %{
          id: wf2_wo2.id,
          last_finished_at: wf2_run2.finished_at,
          workflow_id: job2.workflow_id
        },
        %{
          id: wf2_wo1.id,
          last_finished_at: wf2_run1.finished_at,
          workflow_id: job2.workflow_id
        }
      ]

      assert expected_order == page_two_result

      ### PAGE 3 -----------------------------------------------------------------------

      page_three_result =
        get_simplified_page(
          project,
          %{"page" => 3, "page_size" => 3},
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        )

      # all work_orders in page_three are ordered by finished_at
      expected_order = [
        %{
          id: wf1_wo3.id,
          last_finished_at: wf1_run3.finished_at,
          workflow_id: job1.workflow_id
        },
        %{
          id: wf1_wo2.id,
          last_finished_at: wf1_run2.finished_at,
          workflow_id: job1.workflow_id
        },
        %{
          id: wf1_wo1.id,
          last_finished_at: wf1_run1.finished_at,
          workflow_id: job1.workflow_id
        }
      ]

      assert expected_order == page_three_result
    end

    test "Filtering by status :failure exit_code = 1" do
      project = insert(:project)

      workflow_map = build_workflows(project, ["workflow1", "workflow2"])

      scenario = [
        workflow1: [
          [:success, :success, :success, :failure],
          [:success, :success, :failure, :success]
        ]
      ]

      [%{id: id}] = apply_scenario(project, workflow_map, scenario)

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{"failure" => true})

      assert [] == actual_filter_by_status(project, %{"success" => true})
      assert [] == actual_filter_by_status(project, %{"pending" => true})
      assert [] == actual_filter_by_status(project, %{"timeout" => true})
      assert [] == actual_filter_by_status(project, %{"crash" => true})

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{
                 "success" => true,
                 "failure" => true,
                 "pending" => true,
                 "timeout" => true,
                 "crash" => true
               })
    end

    test "Filtering by status :pending exit_code = nil" do
      project = insert(:project)

      workflow_map = build_workflows(project, ["workflow1", "workflow2"])

      scenario = [
        workflow1: [
          [:success, :success, :success, :pending],
          [:success, :success, :failure, :success]
        ]
      ]

      [%{id: id}] = apply_scenario(project, workflow_map, scenario)

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{"pending" => true})

      assert [] == actual_filter_by_status(project, %{"success" => true})
      assert [] == actual_filter_by_status(project, %{"timeout" => true})
      assert [] == actual_filter_by_status(project, %{"failure" => true})
      assert [] == actual_filter_by_status(project, %{"crash" => true})

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{
                 "success" => true,
                 "failure" => true,
                 "crash" => true,
                 "timeout" => true,
                 "pending" => true
               })
    end

    test "Filtering by status :timeout exit_code = 2" do
      project = insert(:project)

      workflow_map = build_workflows(project, ["workflow1", "workflow2"])

      scenario = [
        # ---workorder1--- last job succeed on 1st attempt, timedout on 2nd attempt
        workflow1: [
          [:success, :success, :success, :timeout],
          [:success, :success, :failure, :success]
        ]
      ]

      [%{id: id}] = apply_scenario(project, workflow_map, scenario)

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{"timeout" => true})

      assert [] == actual_filter_by_status(project, %{"success" => true})
      assert [] == actual_filter_by_status(project, %{"pending" => true})
      assert [] == actual_filter_by_status(project, %{"failure" => true})
      assert [] == actual_filter_by_status(project, %{"crash" => true})

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{
                 "success" => true,
                 "timeout" => true,
                 "pending" => true,
                 "failure" => true,
                 "crash" => true
               })
    end

    test "Filtering by status :crash exit_code > 2" do
      project = insert(:project)

      workflow_map = build_workflows(project, ["workflow1", "workflow2"])

      scenario = [
        workflow1: [
          [:success, :success, :success, :crash],
          [:success, :success, :failure, :success]
        ]
      ]

      [%{id: id}] = apply_scenario(project, workflow_map, scenario)

      assert [%{id: ^id}] = actual_filter_by_status(project, %{"crash" => true})

      assert [] == actual_filter_by_status(project, %{"success" => true})
      assert [] == actual_filter_by_status(project, %{"pending" => true})
      assert [] == actual_filter_by_status(project, %{"failure" => true})
      assert [] == actual_filter_by_status(project, %{"timeout" => true})

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{
                 "success" => true,
                 "failure" => true,
                 "crash" => true,
                 "timeout" => true,
                 "pending" => true
               })
    end

    test "Filtering by status :success exit_code = 0" do
      project = insert(:project)

      workflow_map =
        build_workflows(project, ["workflow1", "workflow2", "workflow3"])

      scenario = [
        workflow1: [
          [:success, :success, :success, :success],
          [:success, :success, :success, :pending],
          [:success, :success, :pending],
          [:success, :success, :success, :failure]
        ],
        workflow2: [
          [:success, :success, :success, :failure],
          [:success, :success, :success, :failure]
        ],
        workflow1: [
          [:success, :success, :success, :failure],
          [:success, :success, :success, :failure]
        ],
        workflow3: [
          [:success, :success, :success, :failure],
          [:success, :success, :success, :failure]
        ]
      ]

      [_, _, _, %{id: id}] = apply_scenario(project, workflow_map, scenario)

      assert [%{id: ^id}] =
               actual_filter_by_status(project, %{"success" => true})

      refute actual_filter_by_status(project, %{"failure" => true})
             |> Enum.any?(fn wo -> wo.id == id end)

      refute actual_filter_by_status(project, %{"pending" => true})
             |> Enum.any?(fn wo -> wo.id == id end)

      refute actual_filter_by_status(project, %{"timeout" => true})
             |> Enum.any?(fn wo -> wo.id == id end)

      refute actual_filter_by_status(project, %{"crash" => true})
             |> Enum.any?(fn wo -> wo.id == id end)

      assert [%{id: ^id} | _] =
               actual_filter_by_status(project, %{
                 "success" => true,
                 "failure" => true,
                 "timeout" => true,
                 "pending" => true,
                 "crash" => true
               })
    end

    test "Filtering by status complex all" do
      project = insert(:project)

      workflow_map = build_workflows(project, ["workflow1", "workflow2"])

      # workflow1 = [job1, job2, job3, job4]
      # workflow2 = [job1, job2, job3, job4]

      scenario = [
        workflow2: [
          [:success, :success, :success, :success],
          [:success, :success, :success, :failure]
        ],
        workflow1: [
          [:success, :success, :timeout],
          [:success, :success, :failure],
          [:success, :success, :failure]
        ],
        workflow2: [
          [:success, :success, :success, :pending],
          [:success, :success, :failure, :failure]
        ],
        workflow1: [
          [:success, :crash],
          [:success, :success, :failure]
        ],
        workflow2: [
          [:success, :success, :success, :failure],
          [:success, :success, :failure, :success]
        ]
      ]

      [
        %{id: id_failure},
        %{id: id_crash},
        %{id: id_pending},
        %{id: id_timeout},
        %{id: id_success}
      ] = apply_scenario(project, workflow_map, scenario)

      assert [%{id: ^id_failure}] =
               actual_filter_by_status(project, %{"failure" => true})

      assert [%{id: ^id_success}] =
               actual_filter_by_status(project, %{"success" => true})

      assert [%{id: ^id_pending}] =
               actual_filter_by_status(project, %{"pending" => true})

      assert [%{id: ^id_timeout}] =
               actual_filter_by_status(project, %{"timeout" => true})

      assert [%{id: ^id_crash}] =
               actual_filter_by_status(project, %{"crash" => true})

      assert [
               %{id: ^id_pending},
               %{id: ^id_success},
               %{id: ^id_timeout},
               %{id: ^id_crash},
               %{id: ^id_failure}
             ] =
               actual_filter_by_status(project, %{
                 "success" => true,
                 "failure" => true,
                 "crash" => true,
                 "timeout" => true,
                 "pending" => true
               })
    end

    test "Filtering by workorder inserted_at" do
      project = insert(:project)

      workflow_map = build_workflows(project, ["workflow1", "workflow2"])

      # workflow1 = [job1, job2, job3, job4]
      # workflow2 = [job1, job2, job3, job4]

      scenario = [
        workflow2: [
          [:success, :success, :success, :success],
          [:success, :success, :success, :failure]
        ],
        workflow1: [
          [:success, :success, :timeout],
          [:success, :success, :failure],
          [:success, :success, :failure]
        ],
        workflow2: [
          [:success, :success, :success, :pending],
          [:success, :success, :failure, :failure]
        ],
        workflow1: [
          [:success, :crash],
          [:success, :success, :failure]
        ],
        workflow2: [
          [:success, :success, :success, :failure],
          [:success, :success, :failure, :success]
        ]
      ]

      [
        %{id: id_failure},
        %{id: id_crash},
        %{id: id_pending},
        %{id: id_timeout},
        %{id: id_success}
      ] =
        apply_scenario(project, workflow_map, scenario)
        |> update_insertion_dates([
          ~U[2022-01-01 00:00:10.000000Z],
          ~U[2022-02-01 00:00:10.000000Z],
          ~U[2022-03-01 00:00:10.000000Z],
          ~U[2022-04-01 00:00:10.000000Z],
          ~U[2022-05-01 00:00:10.000000Z]
        ])

      # after wo inserted_at
      assert [%{id: ^id_pending}, %{id: ^id_success}, %{id: ^id_timeout}] =
               get_simplified_page(
                 project,
                 %{"page" => 1, "page_size" => 10},
                 SearchParams.new(%{
                   "crash" => "true",
                   "failure" => "true",
                   "pending" => "true",
                   "timeout" => "true",
                   "success" => "true",
                   "wo_date_after" => "2022-03-01 00:00:10"
                 })
               )

      # before wo inserted_at
      assert [%{id: ^id_crash}, %{id: ^id_failure}] =
               get_simplified_page(
                 project,
                 %{"page" => 1, "page_size" => 10},
                 SearchParams.new(%{
                   "crash" => "true",
                   "failure" => "true",
                   "pending" => "true",
                   "timeout" => "true",
                   "success" => "true",
                   "wo_date_before" => "2022-03-01 00:00:10"
                 })
               )

      # between wo inserted_at
      assert [%{id: ^id_pending}, %{id: ^id_crash}] =
               get_simplified_page(
                 project,
                 %{"page" => 1, "page_size" => 10},
                 SearchParams.new(%{
                   "crash" => "true",
                   "failure" => "true",
                   "pending" => "true",
                   "timeout" => "true",
                   "success" => "true",
                   "wo_date_after" => "2022-02-01 00:00:10",
                   "wo_date_before" => "2022-04-01 00:00:10"
                 })
               )
    end
  end

  defp build_workflows(project, workflow_names) do
    workflow_names
    |> Enum.reduce(%{}, fn workflow_name, acc ->
      workflow = insert(:workflow, name: workflow_name, project: project)

      jobs =
        Enum.map(1..4, fn job_index ->
          insert(:job, name: "job#{job_index}", project: project)
        end)

      Map.put(acc, workflow_name, [workflow, jobs])
    end)
  end

  defp update_insertion_dates(work_orders, dates) do
    work_orders
    |> Enum.with_index()
    |> Enum.map(fn {%{id: id}, index} ->
      inserted_at = Enum.at(dates, index)

      Repo.get!(Lightning.WorkOrder, id)
      |> Ecto.Changeset.change(inserted_at: inserted_at)
      |> Repo.update()
      |> case do
        {:ok, _} -> %{id: id}
        _ -> nil
      end
    end)
  end

  # a test utility function that creates fixtures based on a pseudo visual (UI) execution scenario
  # [:success, :success, :failure] is an attempt resulting in job0 -> exit_code::success, job1 -> exit_code::success, job2 -> exit_code:1
  defp apply_scenario(project, workflow_map, scenario) do
    seconds = 20

    dataclip = insert(:dataclip, project: project)

    scenario
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {{workflow_name, attempts}, workorder_index} ->
      coeff = workorder_index + 1

      [workflow, jobs] = workflow_map[Atom.to_string(workflow_name)]

      reason = insert(:reason, type: :webhook, dataclip: dataclip)
      wo = insert(:workorder, reason: reason, workflow: workflow)

      attempts
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.each(fn {run_results, attempt_index} ->
        coeff = coeff * (attempt_index + 1)

        runs =
          run_results
          |> Enum.with_index()
          |> Enum.map(fn {exit_result, job_index} ->
            now = Timex.now()
            coeff = coeff * (job_index + 1)
            job = Enum.at(jobs, job_index)

            finished_at =
              now
              |> Timex.shift(seconds: coeff * seconds + 10)

            run = %{
              job_id: job.id,
              started_at:
                now
                |> Timex.shift(seconds: coeff * seconds),
              finished_at: finished_at,
              input_dataclip_id: dataclip.id
            }

            case exit_result do
              :success -> Map.merge(run, %{exit_code: 0})
              :failure -> Map.merge(run, %{exit_code: 1})
              :timeout -> Map.merge(run, %{exit_code: 2})
              :crash -> Map.merge(run, %{exit_code: 3})
              :pending -> Map.merge(run, %{exit_code: nil, finished_at: nil})
            end
          end)

        reason = insert(:reason, type: :webhook, dataclip: dataclip)

        Lightning.Attempt.new(%{
          work_order_id: wo.id,
          reason_id: reason.id,
          runs: runs
        })
        |> Repo.insert()
      end)

      %{id: wo.id}
    end)
  end

  defp actual_filter_by_status(project, status) do
    Invocation.search_workorders(
      %Lightning.Projects.Project{
        id: project.id
      },
      SearchParams.new(status),
      %{"page" => 1, "page_size" => 10}
    ).entries()
  end

  defp create_work_order(project, job, trigger, now, seconds) do
    workflow = job.workflow
    dataclip = insert(:dataclip, project: project)

    reason =
      insert(
        :reason,
        dataclip: dataclip,
        trigger: trigger,
        type: :webhook
      )

    wo =
      insert(
        :workorder,
        reason: reason,
        workflow: workflow
      )

    %{runs: [run]} =
      Lightning.Attempt.new(%{
        work_order_id: wo.id,
        reason_id: reason.id,
        runs: [
          %{
            job_id: job.id,
            started_at: now |> Timex.shift(seconds: seconds),
            finished_at:
              now
              |> Timex.shift(seconds: seconds + 10),
            exit_code: 0,
            input_dataclip_id: dataclip.id
          }
        ]
      })
      |> Repo.insert!()

    %{work_order: wo, run: run}
  end

  defp get_simplified_page(project, page, filter) do
    Invocation.search_workorders(
      %Lightning.Projects.Project{
        id: project.id
      },
      filter,
      page
    ).entries()
  end
end
