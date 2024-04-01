defmodule Lightning.InvocationTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Runs
  alias Lightning.WorkOrders.SearchParams
  alias Lightning.Invocation
  alias Lightning.Invocation.Step
  alias Lightning.Repo

  require SearchParams

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

      step = insert(:step, input_dataclip: dataclip)

      assert Invocation.get_dataclip(step) |> Repo.preload(:project) ==
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

  describe "steps" do
    @invalid_attrs %{job_id: nil}
    @valid_attrs %{
      # Note that we faithfully persist any string the worker sends back.
      exit_reason: "something very strange",
      finished_at: ~U[2022-02-02 11:49:00.000000Z],
      log: [],
      started_at: ~U[2022-02-02 11:49:00.000000Z]
    }

    test "list_steps/0 returns all steps" do
      step = insert(:step)
      assert Invocation.list_steps() |> Enum.map(fn s -> s.id end) == [step.id]
    end

    test "get_step!/1 returns the step with given id" do
      step = insert(:step)

      actual_step = Invocation.get_step!(step.id)

      assert actual_step.id == step.id
      assert actual_step.input_dataclip_id == step.input_dataclip_id
      assert actual_step.job_id == step.job_id
    end

    test "create_step/1 with valid data creates a step" do
      project = insert(:project)
      dataclip = insert(:dataclip, project: project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      assert {:ok, %Step{} = step} =
               Invocation.create_step(
                 Map.merge(@valid_attrs, %{
                   job_id: job.id,
                   input_dataclip_id: dataclip.id
                 })
               )

      assert step.exit_reason == "something very strange"
      assert step |> Invocation.logs_for_step() == []
      assert step.finished_at == ~U[2022-02-02 11:49:00.000000Z]
      assert step.started_at == ~U[2022-02-02 11:49:00.000000Z]
    end

    test "create_step/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Invocation.create_step(@invalid_attrs)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Map.merge(@valid_attrs, %{event_id: Ecto.UUID.generate()})
               |> Invocation.create_step()

      assert event_id:
               {
                 "does not exist",
                 #  TODO - foreign keys? come back?
                 [constraint: :foreign, constraint_name: "runs_event_id_fkey"]
               } in errors
    end

    test "change_step/1 returns a step changeset" do
      step = insert(:step)
      assert %Ecto.Changeset{} = Invocation.change_step(step)
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

    run =
      insert(:run,
        work_order: wo,
        dataclip: dataclip,
        starting_trigger: trigger
      )

    {:ok, step} =
      Runs.start_step(%{
        "run_id" => run.id,
        "job_id" => job.id,
        "input_dataclip_id" => dataclip.id,
        "started_at" => now |> Timex.shift(seconds: seconds),
        "finished_at" =>
          now
          |> Timex.shift(seconds: seconds + 10),
        "step_id" => Ecto.UUID.generate()
      })

    %{work_order: wo, step: step}
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

      runs =
        Enum.map(workorders, fn workorder ->
          insert(:run,
            work_order: workorder,
            dataclip: dataclip,
            starting_trigger: trigger
          )
        end)

      runs
      |> Enum.with_index()
      |> Enum.each(fn {run, index} ->
        started_shift = -50 - index * 10
        finished_shift = -40 - index * 10

        Runs.start_step(%{
          "run_id" => run.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "started_at" => now |> Timex.shift(seconds: started_shift),
          "finished_at" => now |> Timex.shift(seconds: finished_shift),
          "step_id" => Ecto.UUID.generate()
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
    test "filters workorders by two statuses" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      insert_list(3, :workorder, workflow: workflow, state: :pending)
      insert_list(2, :workorder, workflow: workflow, state: :crashed)
      insert_list(2, :workorder, workflow: workflow, state: :failed)
      insert_list(1, :workorder, workflow: workflow, state: :pending)
      insert_list(1, :workorder, workflow: workflow, state: :crashed)

      assert %{
               page_number: 1,
               page_size: 10,
               total_entries: 7,
               total_pages: 1,
               entries: entries
             } =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{"status" => ["pending", "crashed"]}),
                 %{
                   page: 1,
                   page_size: 10
                 }
               )

      assert %{
               :pending => 4,
               :crashed => 3
             } = Enum.map(entries, & &1.state) |> Enum.frequencies()
    end

    test "filters workorders by all statuses" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      count =
        SearchParams.status_list()
        |> Enum.map(fn status ->
          insert(:workorder, workflow: workflow, state: status)
        end)
        |> Enum.count()

      assert %{
               page_number: 1,
               page_size: 10,
               total_entries: ^count,
               total_pages: 1,
               entries: entries
             } =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{"status" => SearchParams.status_list()}),
                 %{
                   page: 1,
                   page_size: 10
                 }
               )

      assert SearchParams.status_list() |> Enum.frequencies() ==
               Enum.map(entries, & &1.state)
               |> Enum.frequencies()
               |> Map.new(fn {status, count} ->
                 {Atom.to_string(status), count}
               end)
    end

    test "returns a sequence of workorders pages" do
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
        Invocation.search_workorders(
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
        Invocation.search_workorders(
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
        Invocation.search_workorders(
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

      %{work_order: wf1_wo1, step: _wf1_step1} =
        create_work_order(project, workflow1, job1, trigger1, now, 10)

      %{work_order: wf1_wo2, step: _wf1_step2} =
        create_work_order(project, workflow1, job1, trigger1, now, 20)

      %{work_order: wf1_wo3, step: _wf1_step3} =
        create_work_order(project, workflow1, job1, trigger1, now, 30)

      {workflow2, trigger2, job2} =
        build_workflow(project: project, name: "workflow-2")

      %{work_order: wf2_wo1, step: _wf2_step1} =
        create_work_order(project, workflow2, job2, trigger2, now, 40)

      %{work_order: wf2_wo2, step: _wf2_step2} =
        create_work_order(project, workflow2, job2, trigger2, now, 50)

      %{work_order: wf2_wo3, step: _wf2_step3} =
        create_work_order(project, workflow2, job2, trigger2, now, 60)

      {workflow3, trigger3, job3} =
        build_workflow(project: project, name: "workflow-3")

      %{work_order: wf3_wo1, step: _wf3_step1} =
        create_work_order(project, workflow3, job3, trigger3, now, 70)

      %{work_order: wf3_wo2, step: _wf3_step2} =
        create_work_order(project, workflow3, job3, trigger3, now, 80)

      %{work_order: wf3_wo3, step: _wf3_step3} =
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
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workflow_id" => workflow1.id})
        ).entries

      assert length(workflow1_results) == 5

      assert Enum.all?(workflow1_results, fn wo ->
               wo.workflow_id == workflow1.id
             end)

      workflow2_results =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workflow_id" => workflow2.id})
        ).entries

      assert length(workflow2_results) == 3

      assert Enum.all?(workflow2_results, fn wo ->
               wo.workflow_id == workflow2.id
             end)
    end

    test "filters workorders by workorder id" do
      project = insert(:project)

      workflow = insert(:workflow, project: project, name: "workflow-1")

      workorder_1 = insert(:workorder, workflow: workflow, state: :success)

      workorder_2 = insert(:workorder, workflow: workflow, state: :success)

      page_result =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workorder_id" => workorder_1.id})
        )

      assert [entry] = page_result.entries
      assert entry.id == workorder_1.id

      page_result =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workorder_id" => workorder_2.id})
        )

      assert [entry] = page_result.entries
      assert entry.id == workorder_2.id
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
        Invocation.search_workorders(
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
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "wo_date_after" => Timex.shift(now, minutes: -1),
            "wo_date_before" => Timex.shift(now, minutes: 1)
          })
        ).entries

      assert found_workorder.id == wo_now.id
    end

    # to be replaced by paginator unit tests
    @tag :skip
    test "filters workorders sets timeout" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      SearchParams.status_list()
      |> Enum.map(fn status ->
        insert_list(1_000, :workorder, workflow: workflow, state: status)
      end)

      try do
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => SearchParams.status_list()}),
          %{
            page: 1,
            page_size: 10,
            options: [timeout: 30]
          }
        )
      rescue
        e in [DBConnection.ConnectionError] ->
          assert e.message =~ "timeout"
      end
    end
  end

  describe "search_workorders_query/2" do
    test "ignores status filter when all statuses are queried" do
      project = insert(:project)

      query =
        Invocation.search_workorders_query(
          project,
          SearchParams.new(%{"status" => ["pending"]})
        )

      {sql, _value} = Repo.to_sql(:all, query)
      assert sql =~ ~S["state" = ]

      query =
        Invocation.search_workorders_query(
          project,
          SearchParams.new(%{"status" => SearchParams.status_list()})
        )

      {sql, _value} = Repo.to_sql(:all, query)
      refute sql =~ ~S["state" = ]
    end
  end

  describe "searching across workorders" do
    setup do
      project = insert(:project)

      dataclip =
        insert(:dataclip,
          body: %{
            "player" => "Sadio Mane",
            "date_of_birth" => "1992-04-10",
            "fav_color" => "vert foncé"
          },
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

      run =
        insert(:run,
          work_order: workorder,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, step} =
        Runs.start_step(%{
          "run_id" => run.id,
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      insert(:log_line,
        run: run,
        step: step,
        message: "Sadio Mane is playing for Senegal",
        timestamp: Timex.now()
      )

      insert(:log_line,
        run: run,
        step: step,
        message: "Bukayo Saka is playing for England",
        timestamp: Timex.now()
      )

      %{
        project: project,
        dataclip: dataclip,
        workorder: workorder,
        run: run,
        step: step
      }
    end

    @tag skip: "Ooops. We don't support this yet."
    test "search on UUIDs can find partial string matches at any point in the dataclip UUID",
         %{project: project, dataclip: dataclip} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => dataclip.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(dataclip.id, 4, 3),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on UUIDs can find partial string matches at any point in the work_order UUID",
         %{project: project, workorder: workorder} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => workorder.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(workorder.id, 4, 3),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on UUIDs can find partial string matches at any point in the run UUID",
         %{project: project, run: run} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => run.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(run.id, 4, 3),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on UUIDs can find partial string matches at any point in the step UUID",
         %{project: project, step: step} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => step.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(step.id, 7, 2),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on logs does NOT return 'stem' matches... only exact matches",
         %{project: project} do
      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "played",
                   "search_fields" => ["log"]
                 })
               ).entries

      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "playings",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    test "search on logs can find partial string matches at the start of words",
         %{project: project} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "Buka",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    @tag skip: "Ooops. We don't support this yet."
    test "search on logs can find partial string matches at the end of words", %{
      project: project
    } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "ngland",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    test "search on logs can find partial string matches across words", %{
      project: project
    } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "Bukayo Sa",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    test "search on dataclips can find partial string matches at the start of keys",
         %{
           project: project
         } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "date_of",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "bir",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "irth",
                   "search_fields" => ["body"]
                 })
               ).entries
    end

    test "search on dataclips can find partial string matches at the start of values",
         %{
           project: project
         } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "vert",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "ncé",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "199",
                   "search_fields" => ["body"]
                 })
               ).entries
    end

    test "filters workorders by search term on body and/or run logs and/or workorder, run, or step ID",
         %{project: project, workorder: workorder, run: run, step: step} do
      assert Invocation.search_workorders(
               project,
               SearchParams.new(%{
                 "search_term" => "won't match anything",
                 "search_fields" => ["body", "log"]
               })
             ).entries == []

      assert [found_workorder] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "senegal",
                   "search_fields" => ["body", "log"]
                 })
               ).entries

      assert found_workorder.id == workorder.id

      assert [] ==
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "senegal",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [] ==
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "liverpool",
                   "search_fields" => ["log"]
                 })
               ).entries

      # By ID
      assert [] ==
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "nonexistentid",
                   "search_fields" => ["id"]
                 })
               ).entries

      # Search by Workorder, Run, or Step IDs and their parts
      search_ids =
        [workorder.id, run.id, step.id]
        |> Enum.map(fn uuid ->
          [part | _t] = String.split(uuid, "-")
          [part, uuid]
        end)
        |> List.flatten()

      for search_id <- search_ids do
        assert [found_workorder] =
                 Invocation.search_workorders(
                   project,
                   SearchParams.new(%{
                     "search_term" => search_id,
                     "search_fields" =>
                       ["id"] ++
                         Enum.take(["body", "log"], Enum.random([0, 1, 2]))
                   })
                 ).entries

        assert found_workorder.id == workorder.id
      end
    end
  end

  describe "step logs" do
    test "logs_for_step/1 returns an array of the logs for a given step" do
      step =
        insert(:step,
          log_lines: ["Hello", "I am a", "log"] |> Enum.map(&build_log_map/1)
        )

      log_lines = Invocation.logs_for_step(step)

      assert Enum.count(log_lines) == 3

      assert log_lines |> Enum.map(fn log_line -> log_line.message end) == [
               "Hello",
               "I am a",
               "log"
             ]
    end

    test "assemble_logs_for_step/1 returns a string representation of the logs for a step" do
      step =
        insert(:step,
          log_lines: ["Hello", "I am a", "log"] |> Enum.map(&build_log_map/1)
        )

      log_string = Invocation.assemble_logs_for_step(step)

      assert log_string == "Hello\nI am a\nlog"
    end

    test "assemble_logs_for_step/1 returns nil when given a nil step" do
      assert Invocation.assemble_logs_for_step(nil) == nil
    end

    defp build_log_map(message) do
      %{id: Ecto.UUID.generate(), message: message, timestamp: build(:timestamp)}
    end
  end
end
