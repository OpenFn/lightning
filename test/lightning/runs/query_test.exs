defmodule Lightning.Runs.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Runs.Query
  alias Lightning.Projects

  describe "lost/1" do
    test "returns only those runs which were claimed before the earliest
    allowable claim date and remain unfinished" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Lightning.current_time()

      default_max_run_duration = Lightning.Config.default_max_run_duration()
      grace_period = Lightning.Config.grace_period()

      default_max = grace_period + default_max_run_duration

      run_to_be_marked_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          claimed_at: DateTime.add(now, -(default_max + 2))
        )

      _crashed_but_NOT_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :crashed,
          claimed_at: DateTime.add(now, -(default_max + 2))
        )

      another_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          claimed_at: DateTime.add(now, 0)
        )

      an_old_run_with_a_long_timeout =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: %Lightning.Runs.RunOptions{
            # set via default to milliseconds, plus 5000 extra seconds
            run_timeout_ms: default_max * 1000 + 5000
          },
          claimed_at: DateTime.add(now, -(default_max + 14))
        )

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)

      assert lost_runs == [run_to_be_marked_lost.id]

      Lightning.Stub.freeze_time(DateTime.add(now, 1, :day))

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)
        |> MapSet.new()

      assert MapSet.equal?(
               lost_runs,
               MapSet.new([
                 run_to_be_marked_lost.id,
                 another_run.id,
                 an_old_run_with_a_long_timeout.id
               ])
             )
    end

    test "falls back properly to system default max duration when options is nil" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Lightning.current_time()

      default_max_run_duration = Lightning.Config.default_max_run_duration()
      grace_period = Lightning.Config.grace_period()

      default_max = grace_period + default_max_run_duration

      should_be_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: nil,
          claimed_at: DateTime.add(now, -(default_max + 2))
        )

      _should_not_be_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: nil,
          claimed_at: DateTime.add(now, -(default_max - 2))
        )

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)

      assert lost_runs == [should_be_lost.id]
    end

    test "with run_timeout_ms=120s and grace_period, run is lost after 120s + grace_period" do
      # A run is considered lost when:
      # (started_at OR claimed_at) + run_timeout_ms + grace_period < now

      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Lightning.current_time()

      # Config values
      grace_period_seconds = Lightning.Config.grace_period()

      # Set a custom run_timeout_ms of 120 seconds (120_000 ms)
      custom_timeout_ms = 120_000
      custom_timeout_seconds = div(custom_timeout_ms, 1000)
      total_allowable_seconds = custom_timeout_seconds + grace_period_seconds

      # Run claimed 1 second before the boundary should NOT be lost
      not_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: custom_timeout_ms},
          claimed_at: DateTime.add(now, -(total_allowable_seconds - 1))
        )

      # Run claimed 1 second past the boundary SHOULD be lost
      past_boundary =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: custom_timeout_ms},
          claimed_at: DateTime.add(now, -(total_allowable_seconds + 1))
        )

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)

      assert past_boundary.id in lost_runs,
             "Run claimed #{total_allowable_seconds + 1}s ago (past 120s timeout + #{grace_period_seconds}s grace) should be lost"

      refute not_lost.id in lost_runs,
             "Run claimed #{total_allowable_seconds - 1}s ago (within 120s timeout + #{grace_period_seconds}s grace) should NOT be lost"
    end

    test "with options=nil, run is lost after default_max_run_duration + grace_period" do
      # When options is nil, the system falls back to:
      # default_max_run_duration (seconds) + grace_period (seconds)

      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Lightning.current_time()

      # System defaults
      default_max_seconds = Lightning.Config.default_max_run_duration()
      grace_period_seconds = Lightning.Config.grace_period()
      total_allowable_seconds = default_max_seconds + grace_period_seconds

      # Run claimed 1 second before the boundary should NOT be lost
      not_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: nil,
          claimed_at: DateTime.add(now, -(total_allowable_seconds - 1))
        )

      # Run claimed 1 second past the boundary SHOULD be lost
      past_boundary =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: nil,
          claimed_at: DateTime.add(now, -(total_allowable_seconds + 1))
        )

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)

      assert past_boundary.id in lost_runs,
             "Run claimed #{total_allowable_seconds + 1}s ago (past #{default_max_seconds}s default + #{grace_period_seconds}s grace) should be lost"

      refute not_lost.id in lost_runs,
             "Run claimed #{total_allowable_seconds - 1}s ago (within #{default_max_seconds}s default + #{grace_period_seconds}s grace) should NOT be lost"
    end

    test "timeout clock uses started_at when available, run lost after timeout from started_at" do
      # The timeout clock starts at COALESCE(started_at, claimed_at)
      # This means if a run has started_at, that takes precedence

      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Lightning.current_time()

      custom_timeout_ms = 60_000
      grace_period_seconds = Lightning.Config.grace_period()

      total_allowable_seconds =
        div(custom_timeout_ms, 1000) + grace_period_seconds

      # Run was claimed long ago but started recently - should NOT be lost
      # (started_at is used for timeout calculation)
      _claimed_long_ago_started_recently =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: custom_timeout_ms},
          claimed_at: DateTime.add(now, -(total_allowable_seconds + 100)),
          started_at: DateTime.add(now, -10)
        )

      # Run was claimed long ago, started long ago - SHOULD be lost
      started_and_exceeded =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: custom_timeout_ms},
          claimed_at: DateTime.add(now, -(total_allowable_seconds + 100)),
          started_at: DateTime.add(now, -(total_allowable_seconds + 1))
        )

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)

      assert lost_runs == [started_and_exceeded.id],
             "Run is lost 60s + #{grace_period_seconds}s after started_at, not claimed_at"
    end

    test "run with 30s timeout is lost after 30s+grace, but 300s timeout run is not" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Lightning.current_time()

      grace_period_seconds = Lightning.Config.grace_period()

      # Short timeout run (30 seconds) - should be lost after 30s + grace
      short_timeout_ms = 30_000
      short_total = div(short_timeout_ms, 1000) + grace_period_seconds

      short_timeout_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: short_timeout_ms},
          claimed_at: DateTime.add(now, -(short_total + 1))
        )

      # Long timeout run (5 minutes = 300s) - should NOT be lost at same elapsed time
      long_timeout_ms = 300_000

      _long_timeout_still_running =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: long_timeout_ms},
          claimed_at: DateTime.add(now, -(short_total + 1))
        )

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)

      assert lost_runs == [short_timeout_lost.id],
             "30s run is lost at #{short_total + 1}s, but 300s run still has #{300 + grace_period_seconds - short_total - 1}s remaining"
    end
  end

  describe "concurrency" do
    test "base case" do
      [red, green, blue, yellow, magenta, cyan] =
        [
          "red",
          "green",
          "blue",
          "yellow",
          "magenta",
          "cyan"
        ]
        |> Enum.map(fn name ->
          project = insert(:project, name: name)
          workflow = insert(:simple_workflow, project: project)

          %{project: project, workflow: workflow}
        end)

      # We cycle through a list of colors to insert runs for each project
      # The contiguous runs for the same project are added so that we
      # can ensure the sorting order for eligible_for_claim is reliable,
      # i.e. items are processed in order of insertion, not by their
      # position in a given project (i.e. `row_number`)
      [red, green, green, green, blue, yellow, magenta, cyan, red, blue, blue]
      |> Stream.cycle()
      |> Stream.take(60)
      |> Enum.map(fn color ->
        insert_run(color, :available)
      end)

      # distribute_run_inserted_at(projects)
      # set the first runs to claimed for projects red and blue
      first_runs_query = get_first_run_for_projects([red, blue])

      from(r in Lightning.Run,
        where: r.id in subquery(first_runs_query),
        update: [set: [state: :claimed, claimed_at: ^DateTime.utc_now()]]
      )
      |> Repo.update_all([])

      first_runs_query = get_first_run_for_projects([blue])

      from(r in Lightning.Run,
        where: r.id in subquery(first_runs_query),
        update: [set: [state: :claimed, claimed_at: ^DateTime.utc_now()]]
      )
      |> Repo.update_all([])

      first_runs_query = get_first_run_for_projects([blue])

      from(r in Lightning.Run,
        where: r.id in subquery(first_runs_query),
        update: [set: [state: :claimed, claimed_at: ^DateTime.utc_now()]]
      )
      |> Repo.update_all([])

      assert number_of_runs_for_project(red, :available) == 10
      assert number_of_runs_for_project(blue, :available) == 13

      demand = 1

      # claim items in the order of the in_progress_window query
      Query.in_progress_window()
      |> Repo.all()
      |> tap(fn ip ->
        assert length(ip) == 60

        assert Enum.count(
                 ip,
                 fn item ->
                   item.state == :claimed and item.project_id == blue.project.id
                 end
               ) == 3

        assert Enum.count(
                 ip,
                 fn item ->
                   item.state == :claimed and item.project_id == red.project.id
                 end
               ) == 1
      end)
      |> Enum.with_index()
      |> Enum.each(fn {window_item, i} ->
        # Test the actual claiming behavior instead of inspecting internal structure
        if window_item.state == "available" do
          # Get current state before claiming
          available_count_before =
            from(r in Lightning.Run,
              where: r.state == :available,
              select: count()
            )
            |> Repo.one()

          {:ok, [run]} =
            Lightning.Runs.Queue.claim(demand, Query.eligible_for_claim())

          # Verify the right run was claimed
          assert run.id == window_item.id,
                 """
                 Expected run id to be #{window_item.id}, got #{run.id} at index #{i}.
                 Available count before: #{available_count_before}
                 """

          # Verify state changed correctly
          assert %{state: :claimed} = Repo.reload!(run)
        end
      end)
    end

    test "in_progress_window/0" do
      [red, _green, blue, cyan, magenta] =
        [
          {"red", 1},
          {"green", 2},
          {"blue", 3},
          {"cyan", nil},
          {"magenta", nil}
        ]
        |> Enum.map(fn {name, concurrency} ->
          project = insert(:project, name: name)

          workflow =
            insert(:simple_workflow, project: project, concurrency: concurrency)

          %{project: project, workflow: workflow}
        end)

      # magenta project has only project level concurrecy
      Repo.update!(Projects.change_project(magenta.project, %{concurrency: 1}))

      runs_in_order =
        [
          insert_run(red, :available),
          for _ <- 1..10 do
            insert_run(cyan, :available)
          end,
          insert_run(magenta, :available),
          insert_run(blue, :claimed),
          insert_run(blue, :claimed),
          insert_run(blue, :available)
        ]
        |> List.flatten()
        |> Enum.zip_with(
          [
            %{project_id: red.project.id, row_number: 1, concurrency: 1},
            %{project_id: cyan.project.id, row_number: 1, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 2, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 3, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 4, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 5, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 6, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 7, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 8, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 9, concurrency: nil},
            %{project_id: cyan.project.id, row_number: 10, concurrency: nil},
            %{project_id: magenta.project.id, row_number: 1, concurrency: 1},
            %{project_id: blue.project.id, row_number: 1, concurrency: 3},
            %{project_id: blue.project.id, row_number: 2, concurrency: 3},
            %{project_id: blue.project.id, row_number: 3, concurrency: 3}
          ],
          fn run, extra ->
            Map.take(run, [:id, :state, :inserted_at, :priority])
            |> Map.merge(extra)
          end
        )

      window =
        Query.in_progress_window()
        |> Repo.all()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      assert match?(^runs_in_order, window)

      # mark the first run for project red as claimed
      # mark 6 runs for project cyan as claimed
      now = build(:timestamp)

      Repo.update_all(
        from(r in Lightning.Run,
          join:
            s in subquery(
              from(r in Lightning.Run,
                join: wo in assoc(r, :work_order),
                join: wf in assoc(wo, :workflow),
                where:
                  r.state == :available and
                    wf.project_id in ^[red.project.id, cyan.project.id],
                limit: 7,
                select: r,
                update: []
              )
            ),
          on: r.id == s.id
        ),
        set: [state: :claimed, claimed_at: now]
      )

      window =
        Query.in_progress_window()
        |> Repo.all()
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      assert Enum.count(
               window,
               fn item ->
                 item.state == :claimed and item.project_id == red.project.id
               end
             ) == 1,
             "there should be one claimed run for project red"

      assert Enum.count(
               window,
               fn item ->
                 item.state == :claimed and item.project_id == cyan.project.id
               end
             ) == 6,
             "there should be 6 claimed runs for project cyan"

      num_runs = length(runs_in_order)

      runs_in_order_match =
        runs_in_order
        |> Enum.zip_with(
          List.duplicate(%{state: :claimed}, 7) ++
            List.duplicate(%{}, num_runs - 7),
          &Map.merge(&1, &2)
        )

      assert match?(^runs_in_order_match, window), """
      Expected the first 7 to be claimed.
      Being one red and 6 cyan.
      #{inspect(window, pretty: true)}
      """
    end

    test "eligible_for_claim/0 respecting workflow and project concurrency" do
      # we need 2 projects, each with one workflow, called: red, green and blue
      # red should have a limit of 1 (from the workflow)
      # green should have a limit of 2 (from the project)
      # blue has unlimited concurrency

      [red, green, blue] =
        [
          {"red", 1},
          {"green", nil},
          {"blue", nil}
        ]
        |> Enum.map(fn {name, concurrency} ->
          project = insert(:project, name: name)

          workflow =
            insert(:simple_workflow, project: project, concurrency: concurrency)

          %{project: project, workflow: workflow}
        end)

      for _ <- 1..2 do
        insert_run(red, :available)
      end

      for _ <- 1..2 do
        insert_run(green, :available)
      end

      for _ <- 1..3 do
        insert_run(blue, :available)
      end

      # green project has only project level concurrency
      Repo.update!(Projects.change_project(green.project, %{concurrency: 2}))

      # 1st claim (a red)
      {:ok, [%{id: claimed_run_id} = red_run_1]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      red_project_id = red.project.id
      green_project_id = green.project.id
      blue_project_id = blue.project.id

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     id: ^claimed_run_id,
                     project_id: ^red_project_id,
                     state: :claimed,
                     row_number: 1,
                     concurrency: 1
                   },
                   %{
                     project_id: ^red_project_id,
                     state: :available,
                     row_number: 2,
                     concurrency: 1
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available,
                     row_number: 1,
                     concurrency: 2
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available,
                     row_number: 2,
                     concurrency: 2
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available,
                     row_number: 1,
                     concurrency: nil
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available,
                     row_number: 2,
                     concurrency: nil
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available,
                     row_number: 3,
                     concurrency: nil
                   }
                 ],
                 in_progress
               )
      end)

      # 2nd claim (a green)
      {:ok, [%{id: claimed_run_id}]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     project_id: ^red_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^red_project_id,
                     state: :available
                   },
                   %{
                     id: ^claimed_run_id,
                     project_id: ^green_project_id,
                     state: :claimed,
                     row_number: 1,
                     concurrency: 2
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available,
                     row_number: 2,
                     concurrency: 2
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available
                   }
                 ],
                 in_progress
               ),
               """
               red should still be available because of concurrency 1
               #{inspect(in_progress, pretty: true)}
               """
      end)

      # Mark the first red run as finished
      Ecto.Changeset.change(red_run_1,
        state: :success,
        finished_at: build(:timestamp)
      )
      |> Repo.update()

      # 3rd claim (another red, the oldest among all projects)
      {:ok, [%{id: claimed_run_id}]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     id: ^claimed_run_id,
                     project_id: ^red_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^blue_project_id,
                     state: :available
                   }
                 ],
                 in_progress
               ),
               """
               the next red should be claimed because the first one is finished
               #{inspect(in_progress, pretty: true)}
               """
      end)
    end

    # As per commit 16294834 the query gets unecessarily complex
    # once the LV does NOT allow a worfklow concurrency sum to be greater than the project concurrency.
    test "eligible_for_claim/0 respects serial project concurrency" do
      # these are the projects
      # red: has a workflow concurrecy of 2 runs and takes precedence over project concurrency
      # orange: has only project concurrency set to 1
      # green: has workflow concurrency of 2 runs

      [red, orange, green] =
        [
          {"red", 2},
          {"orange", nil},
          {"green", 2}
        ]
        |> Enum.map(fn {name, concurrency} ->
          project = insert(:project, name: name)

          workflow1 =
            insert(:simple_workflow, project: project, concurrency: concurrency)

          workflow2 =
            if name in ["red", "orange"],
              do:
                insert(:simple_workflow,
                  project: project,
                  concurrency: concurrency
                )

          %{project: project, workflow1: workflow1, workflow2: workflow2}
        end)

      insert_run(red, :available, red.workflow1)
      insert_run(red, :available, red.workflow2)

      insert_run(orange, :available, orange.workflow1)
      insert_run(orange, :available, orange.workflow2)

      insert_run(green, :available, green.workflow1)
      insert_run(green, :available, green.workflow1)

      # red workflow concurrency takes precedence over project
      Repo.update!(Projects.change_project(red.project, %{concurrency: 3}))
      # orange project has only project level concurrecy
      Repo.update!(Projects.change_project(orange.project, %{concurrency: 1}))

      {:ok, [%{id: claimed_run_id} = red_run_1]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      red_project_id = red.project.id
      orange_project_id = orange.project.id
      green_project_id = green.project.id

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     id: ^claimed_run_id,
                     project_id: ^red_project_id,
                     state: :claimed,
                     row_number: 1,
                     concurrency: 2
                   },
                   %{
                     project_id: ^red_project_id,
                     state: :available,
                     row_number: 1,
                     concurrency: 2
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :available,
                     row_number: 1,
                     concurrency: 1
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :available,
                     row_number: 2,
                     concurrency: 1
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available,
                     row_number: 1,
                     concurrency: 2
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available,
                     row_number: 2,
                     concurrency: 2
                   }
                 ],
                 in_progress
               )
      end)

      {:ok, [%{id: claimed_run_id} = _red_workflow2]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     project_id: ^red_project_id,
                     state: :claimed
                   },
                   %{
                     id: ^claimed_run_id,
                     project_id: ^red_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available
                   }
                 ],
                 in_progress
               ),
               """
               red continue with 1 claimed (serial execution) and next claimed is an orange one
               #{inspect(in_progress, pretty: true)}
               """
      end)

      # Mark the first red run as finished
      Ecto.Changeset.change(red_run_1,
        state: :success,
        finished_at: build(:timestamp)
      )
      |> Repo.update()

      {:ok, [%{id: claimed_run_id}]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     project_id: ^red_project_id,
                     state: :claimed
                   },
                   %{
                     id: ^claimed_run_id,
                     project_id: ^orange_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available
                   }
                 ],
                 in_progress
               ),
               """
               the next red should be claimed because the first one is finished
               #{inspect(in_progress, pretty: true)}
               """
      end)

      {:ok, [%{id: claimed_run_id} = _green1]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     project_id: ^red_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :available
                   },
                   %{
                     id: ^claimed_run_id,
                     project_id: ^green_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :available
                   }
                 ],
                 in_progress
               ),
               """
               the first green should be claimed as the orange project has serial concurrency
               #{inspect(in_progress, pretty: true)}
               """
      end)

      {:ok, [%{id: claimed_run_id} = _green2]} =
        Lightning.Runs.Queue.claim(1, Query.eligible_for_claim())

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     project_id: ^red_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :claimed
                   },
                   %{
                     project_id: ^orange_project_id,
                     state: :available
                   },
                   %{
                     project_id: ^green_project_id,
                     state: :claimed
                   },
                   %{
                     id: ^claimed_run_id,
                     project_id: ^green_project_id,
                     state: :claimed
                   }
                 ],
                 in_progress
               ),
               """
               the second green should be claimed since it doesn't have serial project concurrency
               #{inspect(in_progress, pretty: true)}
               """
      end)
    end

    test "eligible_for_claim/0 with multiple claims" do
      # we need 3 projects, each with one workflow, called: red, green, blue
      # red should have a limit of 1
      # green should have a limit of 2
      # blue should have a limit of 3

      [red, green, blue] =
        [
          {"red", 1},
          {"green", 2},
          {"blue", 3}
        ]
        |> Enum.map(fn {name, concurrency} ->
          project = insert(:project, name: name)

          workflow =
            insert(:simple_workflow, project: project, concurrency: concurrency)

          %{project: project, workflow: workflow}
        end)

      [red_run_1_id, red_run_2_id] =
        1..2
        |> Enum.map(fn _ ->
          %{id: run_id} = insert_run(red, :available)
          run_id
        end)

      [green_run_1_id, green_run_2_id, green_run_3_id] =
        1..3
        |> Enum.map(fn _ ->
          %{id: run_id} = insert_run(green, :available)
          run_id
        end)

      [blue_run_1_id, blue_run_2_id, blue_run_3_id, blue_run_4_id] =
        1..4
        |> Enum.map(fn _ ->
          %{id: run_id} = insert_run(blue, :available)
          run_id
        end)

      assert {:ok, _} = Lightning.Runs.Queue.claim(7, Query.eligible_for_claim())

      red_project_id = red.project.id
      green_project_id = green.project.id
      blue_project_id = blue.project.id

      Query.in_progress_window()
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> then(fn in_progress ->
        assert match?(
                 [
                   %{
                     id: ^red_run_1_id,
                     project_id: ^red_project_id,
                     state: :claimed,
                     row_number: 1,
                     concurrency: 1
                   },
                   %{
                     id: ^red_run_2_id,
                     project_id: ^red_project_id,
                     state: :available,
                     row_number: 2,
                     concurrency: 1
                   },
                   %{
                     id: ^green_run_1_id,
                     project_id: ^green_project_id,
                     state: :claimed,
                     row_number: 1,
                     concurrency: 2
                   },
                   %{
                     id: ^green_run_2_id,
                     project_id: ^green_project_id,
                     state: :claimed,
                     row_number: 2,
                     concurrency: 2
                   },
                   %{
                     id: ^green_run_3_id,
                     project_id: ^green_project_id,
                     state: :available,
                     row_number: 3,
                     concurrency: 2
                   },
                   %{
                     id: ^blue_run_1_id,
                     project_id: ^blue_project_id,
                     state: :claimed,
                     row_number: 1,
                     concurrency: 3
                   },
                   %{
                     id: ^blue_run_2_id,
                     project_id: ^blue_project_id,
                     state: :claimed,
                     row_number: 2,
                     concurrency: 3
                   },
                   %{
                     id: ^blue_run_3_id,
                     project_id: ^blue_project_id,
                     state: :claimed,
                     row_number: 3,
                     concurrency: 3
                   },
                   %{
                     id: ^blue_run_4_id,
                     project_id: ^blue_project_id,
                     state: :available,
                     row_number: 4,
                     concurrency: 3
                   }
                 ],
                 in_progress
               )
      end)
    end
  end

  def number_of_runs_for_project(color, state \\ :available) do
    project = color.project

    from(r in Lightning.Run,
      join: wo in assoc(r, :work_order),
      join: w in assoc(wo, :workflow),
      join: p in assoc(w, :project),
      where: p.id == ^project.id and r.state == ^state,
      select: count(r.id)
    )
    |> Repo.one()
  end

  defp get_first_run_for_projects(colors) do
    project_names = colors |> Enum.map(& &1.project.name)

    from(r in Lightning.Run,
      join: wo in assoc(r, :work_order),
      join: w in assoc(wo, :workflow),
      join: p in assoc(w, :project),
      where: p.name in ^project_names,
      where: r.state == :available,
      distinct: p.id,
      order_by: [asc: r.inserted_at],
      select: r.id
    )
  end

  defp insert_run(project_workflow_pair, state, workflow \\ nil) do
    workflow = workflow || project_workflow_pair.workflow

    case state do
      :available ->
        [state: state]

      :claimed ->
        [state: state, claimed_at: fn -> build(:timestamp) end]
    end
    |> Keyword.merge(
      work_order: insert(:workorder, workflow: workflow),
      inserted_at: build(:timestamp),
      starting_job: hd(workflow.jobs),
      dataclip: params_with_assocs(:dataclip)
    )
    |> then(fn params -> insert(:run, params) end)
  end
end
