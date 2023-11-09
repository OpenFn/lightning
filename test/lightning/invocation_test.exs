defmodule Lightning.InvocationTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Attempts
  alias Lightning.WorkOrders.SearchParams
  alias Lightning.Invocation
  alias Lightning.Invocation.Run
  alias Lightning.Repo

  defp build_workflow(opts) do
    job = build(:job)
    trigger = build(:trigger)

    workflow =
      build(:workflow, opts)
      |> with_job(job)
      |> with_trigger(trigger)
      |> with_edge({trigger, job})
      |> insert()

    {Repo.reload!(workflow), Repo.reload!(trigger), Repo.reload!(job)}
  end

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
      dataclip = insert(:dataclip, body: nil)

      assert Invocation.get_dataclip!(dataclip.id) |> Repo.preload(:project) ==
               dataclip

      assert_raise Ecto.NoResultsError, fn ->
        Invocation.get_dataclip!(Ecto.UUID.generate())
      end
    end

    test "get_dataclip/1 returns the dataclip with given id" do
      dataclip = insert(:dataclip, body: nil)

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
      dataclip = insert(:dataclip, body: nil)

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_dataclip(dataclip, @invalid_attrs)

      assert dataclip ==
               Invocation.get_dataclip!(dataclip.id)
               |> Repo.preload(:project)
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
      assert run |> Invocation.logs_for_run() == []
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

    test "delete_run/1 deletes the run" do
      run = insert(:run)
      assert {:ok, %Run{}} = Invocation.delete_run(run)
      assert_raise Ecto.NoResultsError, fn -> Invocation.get_run!(run.id) end
    end

    test "change_run/1 returns a run changeset" do
      run = insert(:run)
      assert %Ecto.Changeset{} = Invocation.change_run(run)
    end
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

  defp create_work_order(project, workflow, job, trigger, now, seconds) do
    dataclip = insert(:dataclip, project: project)

    wo =
      insert(
        :workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

    attempt =
      insert(:attempt,
        work_order: wo,
        dataclip: dataclip,
        starting_trigger: trigger
      )

    {:ok, run} =
      Attempts.start_run(%{
        "attempt_id" => attempt.id,
        "job_id" => job.id,
        "input_dataclip_id" => dataclip.id,
        "started_at" => now |> Timex.shift(seconds: seconds),
        "finished_at" =>
          now
          |> Timex.shift(seconds: seconds + 10),
        "run_id" => Ecto.UUID.generate()
      })

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

  describe "search_workorders/1" do
    test "returns workorders ordered inserted at desc, with nulls first" do
      project = insert(:project)
      dataclip = insert(:dataclip)

      {workflow, trigger, job} =
        build_workflow(project: project, name: "chw-help")

      workorders =
        insert_list(4, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Timex.now()

      attempts =
        Enum.map(workorders, fn workorder ->
          insert(:attempt,
            work_order: workorder,
            dataclip: dataclip,
            starting_trigger: trigger
          )
        end)

      attempts
      |> Enum.with_index()
      |> Enum.each(fn {attempt, index} ->
        started_shift = -50 - index * 10
        finished_shift = -40 - index * 10

        Attempts.start_run(%{
          "attempt_id" => attempt.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "started_at" => now |> Timex.shift(seconds: started_shift),
          "finished_at" => now |> Timex.shift(seconds: finished_shift),
          "run_id" => Ecto.UUID.generate()
        })
      end)

      found_workorders =
        Invocation.search_workorders(%Lightning.Projects.Project{
          id: workflow.project_id
        })

      assert found_workorders.page_number() == 1
      assert found_workorders.total_pages() == 1

      assert workorders
             |> Enum.reverse()
             |> Enum.map(fn workorder -> workorder.id end) ==
               found_workorders.entries()
               |> Enum.map(fn workorder -> workorder.id end)
    end
  end

  describe "search_workorders/3" do
    test "returns paginated workorders" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      insert_list(10, :workorder, workflow: workflow, state: :crashed)

      %{
        page_number: page_number,
        page_size: page_size,
        total_entries: total_entries,
        total_pages: total_pages,
        entries: entries
      } =
        Lightning.Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => ["crashed"]}),
          %{
            page: 1,
            page_size: 4
          }
        )

      assert {page_number, page_size, total_entries, total_pages,
              length(entries)} == {1, 4, 10, 3, 4}

      %{
        page_number: page_number,
        page_size: page_size,
        total_entries: total_entries,
        total_pages: total_pages,
        entries: entries
      } =
        Lightning.Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => ["crashed"]}),
          %{
            page: 2,
            page_size: 4
          }
        )

      assert {page_number, page_size, total_entries, total_pages,
              length(entries)} == {2, 4, 10, 3, 4}

      %{
        page_number: page_number,
        page_size: page_size,
        total_entries: total_entries,
        total_pages: total_pages,
        entries: entries
      } =
        Lightning.Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => ["crashed"]}),
          %{
            page: 3,
            page_size: 4
          }
        )

      assert {page_number, page_size, total_entries, total_pages,
              length(entries)} == {3, 4, 10, 3, 2}
    end

    test "returns paginated workorders with ordering" do
      project = insert(:project)

      {workflow1, trigger1, job1} =
        build_workflow(project: project, name: "workflow-1")

      now = Timex.now()

      %{work_order: wf1_wo1, run: _wf1_run1} =
        create_work_order(project, workflow1, job1, trigger1, now, 10)

      %{work_order: wf1_wo2, run: _wf1_run2} =
        create_work_order(project, workflow1, job1, trigger1, now, 20)

      %{work_order: wf1_wo3, run: _wf1_run3} =
        create_work_order(project, workflow1, job1, trigger1, now, 30)

      {workflow2, trigger2, job2} =
        build_workflow(project: project, name: "workflow-2")

      %{work_order: wf2_wo1, run: _wf2_run1} =
        create_work_order(project, workflow2, job2, trigger2, now, 40)

      %{work_order: wf2_wo2, run: _wf2_run2} =
        create_work_order(project, workflow2, job2, trigger2, now, 50)

      %{work_order: wf2_wo3, run: _wf2_run3} =
        create_work_order(project, workflow2, job2, trigger2, now, 60)

      {workflow3, trigger3, job3} =
        build_workflow(project: project, name: "workflow-3")

      %{work_order: wf3_wo1, run: _wf3_run1} =
        create_work_order(project, workflow3, job3, trigger3, now, 70)

      %{work_order: wf3_wo2, run: _wf3_run2} =
        create_work_order(project, workflow3, job3, trigger3, now, 80)

      %{work_order: wf3_wo3, run: _wf3_run3} =
        create_work_order(project, workflow3, job3, trigger3, now, 90)

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

      expected_order = [wf3_wo3.id, wf3_wo2.id, wf3_wo1.id]

      assert expected_order ==
               page_one_result |> Enum.map(fn workorder -> workorder.id end)

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
      expected_order = [wf2_wo3.id, wf2_wo2.id, wf2_wo1.id]

      assert expected_order ==
               page_two_result |> Enum.map(fn workorder -> workorder.id end)

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
      expected_order = [wf1_wo3.id, wf1_wo2.id, wf1_wo1.id]

      assert expected_order ==
               page_three_result |> Enum.map(fn workorder -> workorder.id end)
    end

    test "filters workorders by state" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      pending_workorder = insert(:workorder, workflow: workflow, state: :pending)
      running_workorder = insert(:workorder, workflow: workflow, state: :running)
      success_workorder = insert(:workorder, workflow: workflow, state: :success)
      crashed_workorder = insert(:workorder, workflow: workflow, state: :crashed)
      failed_workorder = insert(:workorder, workflow: workflow, state: :failed)
      killed_workorder = insert(:workorder, workflow: workflow, state: :killed)

      [found_pending_workorder] =
        actual_filter_by_status(project, %{"status" => ["pending"]})

      [found_running_workorder] =
        actual_filter_by_status(project, %{"status" => ["running"]})

      [found_success_workorder] =
        actual_filter_by_status(project, %{"status" => ["success"]})

      [found_crashed_workorder] =
        actual_filter_by_status(project, %{"status" => ["crashed"]})

      [found_failed_workorder] =
        actual_filter_by_status(project, %{"status" => ["failed"]})

      [found_killed_workorder] =
        actual_filter_by_status(project, %{"status" => ["killed"]})

      assert found_pending_workorder.id == pending_workorder.id
      assert found_running_workorder.id == running_workorder.id
      assert found_success_workorder.id == success_workorder.id
      assert found_crashed_workorder.id == crashed_workorder.id
      assert found_failed_workorder.id == failed_workorder.id
      assert found_killed_workorder.id == killed_workorder.id
    end

    test "filters workorders by workflow id" do
      project = insert(:project)

      workflow1 = insert(:workflow, project: project, name: "workflow-1")
      workflow2 = insert(:workflow, project: project, name: "workflow-2")

      insert_list(5, :workorder, workflow: workflow1, state: :success)
      insert_list(3, :workorder, workflow: workflow2, state: :crashed)

      workflow1_results =
        Lightning.Invocation.search_workorders(
          project,
          SearchParams.new(%{"workflow_id" => workflow1.id})
        ).entries

      assert length(workflow1_results) == 5

      assert Enum.all?(workflow1_results, fn wo ->
               wo.workflow_id == workflow1.id
             end)

      workflow2_results =
        Lightning.Invocation.search_workorders(
          project,
          SearchParams.new(%{"workflow_id" => workflow2.id})
        ).entries

      assert length(workflow2_results) == 3

      assert Enum.all?(workflow2_results, fn wo ->
               wo.workflow_id == workflow2.id
             end)
    end

    test "filters workorders by last_activity" do
      project = insert(:project)
      _dataclip = insert(:dataclip)

      {workflow, _trigger, _job} =
        build_workflow(project: project, name: "chw-help")

      now = Timex.now()
      past_time = Timex.shift(now, days: -1)
      future_time = Timex.shift(now, days: 1)

      _wo_past =
        insert(:workorder,
          workflow: workflow,
          inserted_at: past_time,
          last_activity: past_time
        )

      wo_now =
        insert(:workorder,
          workflow: workflow,
          inserted_at: past_time,
          last_activity: now
        )

      _wo_future =
        insert(:workorder,
          workflow: workflow,
          inserted_at: past_time,
          last_activity: future_time
        )

      [found_workorder] =
        Lightning.Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "date_after" => Timex.shift(now, minutes: -1),
            "date_before" => Timex.shift(now, minutes: 1)
          })
        ).entries

      assert found_workorder.id == wo_now.id
    end

    test "filters workorders by workorder inserted_at" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      now = Timex.now()
      past_time = Timex.shift(now, days: -1)
      future_time = Timex.shift(now, days: 1)

      insert(:workorder, workflow: workflow, inserted_at: past_time)
      wo_now = insert(:workorder, workflow: workflow, inserted_at: now)
      insert(:workorder, workflow: workflow, inserted_at: future_time)

      [found_workorder] =
        Lightning.Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "wo_date_after" => Timex.shift(now, minutes: -1),
            "wo_date_before" => Timex.shift(now, minutes: 1)
          })
        ).entries

      assert found_workorder.id == wo_now.id
    end

    test "filters workorders by search term on body and/or run logs" do
      project = insert(:project)

      dataclip =
        insert(:dataclip,
          body: %{"player" => "Sadio Mane"},
          type: :global,
          project: project
        )

      {workflow, trigger, job} =
        build_workflow(project: project, name: "chw-help")

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      attempt =
        insert(:attempt,
          work_order: workorder,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, run} =
        Attempts.start_run(%{
          "attempt_id" => attempt.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "run_id" => Ecto.UUID.generate()
        })

      %Lightning.Invocation.LogLine{
        attempt: attempt,
        run: run,
        message: "Sadio Mane is playing in Senegal and Al Nasr",
        timestamp: Timex.now()
      }
      |> Repo.insert!()

      assert Lightning.Invocation.search_workorders(
               project,
               SearchParams.new(%{
                 "search_term" => "won't match anything",
                 "search_fields" => ["body", "log"]
               })
             ).entries == []

      assert [found_workorder] =
               Lightning.Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "senegal",
                   "search_fields" => ["body", "log"]
                 })
               ).entries

      assert found_workorder.id == workorder.id

      assert [] ==
               Lightning.Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "senegal",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [] ==
               Lightning.Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "liverpool",
                   "search_fields" => ["log"]
                 })
               ).entries
    end
  end

  describe "run logs" do
    test "logs_for_run/1 returns an array of the logs for a given run" do
      run =
        insert(:run,
          log_lines: [
            %{message: "Hello", timestamp: build(:timestamp)},
            %{message: "I am a", timestamp: build(:timestamp)},
            %{message: "log", timestamp: build(:timestamp)}
          ]
        )

      log_lines = Invocation.logs_for_run(run)

      assert Enum.count(log_lines) == 3

      assert log_lines |> Enum.map(fn log_line -> log_line.message end) == [
               "Hello",
               "I am a",
               "log"
             ]
    end

    test "assemble_logs_for_run/1 returns a string representation of the logs for a run" do
      run =
        insert(:run,
          log_lines: [
            %{message: "Hello", timestamp: build(:timestamp)},
            %{message: "I am a", timestamp: build(:timestamp)},
            %{message: "log", timestamp: build(:timestamp)}
          ]
        )

      log_string = Invocation.assemble_logs_for_run(run)

      assert log_string == "Hello\nI am a\nlog"
    end

    test "assemble_logs_for_run/1 returns nil when given a nil run" do
      assert Invocation.assemble_logs_for_run(nil) == nil
    end
  end
end
