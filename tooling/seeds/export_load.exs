# Seeds the dev database with a large work order history, so the
# Lightning.WorkOrders.ExportWorker DBConnection timeout can be reproduced
# locally.
#
#     mix run tooling/seeds/export_load.exs
#
# The history covers every work order state the workflow health page draws, with
# a spread of error signatures, so the same seed doubles as fixture data for
# that page. It is much smaller than the export test needs — logs and dataclips
# are what make the export slow, and the health page reads neither:
#
#     WORK_ORDERS=400 LOGS_PER_RUN=2 DATACLIP_POOL=50 DATACLIP_BYTES=500 \
#       SPREAD_DAYS=45 PROJECT_NAME=health-test \
#       mix run tooling/seeds/export_load.exs
#
# `SPREAD_DAYS` past 30 puts some of the history outside the health page's
# window, which is how you check the window actually excludes anything.
#
# Everything is tunable with env vars (defaults in parentheses):
#
#     WORK_ORDERS=3000        # work orders to create
#     RUNS_PER_WO=2           # runs per work order
#     STEPS_PER_RUN=3         # steps per run
#     LOGS_PER_RUN=40         # log lines per run
#     LOG_LINE_BYTES=250      # size of each log message
#     DATACLIP_POOL=1500      # distinct dataclips created (shared by steps)
#     DATACLIP_BYTES=30000    # uncompressed size of each dataclip body
#     SPREAD_DAYS=30          # spread inserted_at over the last N days
#     PROJECT_NAME=export-load-test
#     USER_EMAIL=super@openfn.org
#
# Re-running the script appends another batch of history to the same project.

require Logger

# Ecto's query logging is per-statement debug output; it would dwarf the work.
Logger.configure(level: :info)

alias Lightning.Accounts
alias Lightning.Invocation.Dataclip
alias Lightning.Invocation.LogLine
alias Lightning.Invocation.Step
alias Lightning.Jobs
alias Lightning.Projects
alias Lightning.Repo
alias Lightning.Run
alias Lightning.RunStep
alias Lightning.WorkOrder
alias Lightning.Workflows
alias Lightning.Workflows.Snapshot

defmodule ExportLoadSeed do
  @moduledoc false

  # Postgres caps a statement at 65535 parameters; these chunk sizes keep every
  # insert_all well under it while still batching usefully.
  @wo_chunk 200
  @dataclip_chunk 50
  @log_chunk 1000

  # Every state the workflow health page draws, with success still dominating:
  # half, then 10% failed and 5% each of the rest.
  @wo_states %{
    0 => :failed,
    1 => :failed,
    2 => :crashed,
    3 => :cancelled,
    4 => :killed,
    5 => :exception,
    6 => :lost,
    7 => :rejected,
    8 => :running,
    9 => :pending
  }

  @in_flight [:available, :started]

  # What the run and its last step report, so the triage table gets a spread of
  # real signatures rather than one row of `fail:unknown`. A `nil` step
  # error_type is the common shape — `mark_steps_lost/1` and the worker's cancel
  # path stamp the reason and leave the type to the run.
  @failures %{
    crashed: {"CompileError", nil, nil},
    cancelled: {"Cancelled", "cancel", nil},
    killed: {"OOMError", "kill", nil},
    exception: {"ExecutionError", "exception", nil},
    lost: {"LostAfterStart", "lost", nil}
  }

  # `:failed` rotates through a few types so the table has more than one row to
  # sort; the rest are one signature each.
  @failed_types ["RuntimeError", "JobError", "AdaptorError", "TimeoutError"]

  def config do
    %{
      work_orders: int("WORK_ORDERS", 3_000),
      runs_per_wo: int("RUNS_PER_WO", 2),
      steps_per_run: int("STEPS_PER_RUN", 3),
      logs_per_run: int("LOGS_PER_RUN", 40),
      log_line_bytes: int("LOG_LINE_BYTES", 250),
      dataclip_pool: int("DATACLIP_POOL", 1_500),
      dataclip_bytes: int("DATACLIP_BYTES", 30_000),
      spread_days: int("SPREAD_DAYS", 30),
      project_name: System.get_env("PROJECT_NAME", "export-load-test"),
      user_email: System.get_env("USER_EMAIL", "super@openfn.org")
    }
  end

  defp int(key, default) do
    System.get_env(key, to_string(default)) |> String.to_integer()
  end

  def run(config) do
    log("config: #{inspect(config)}")

    user = find_user!(config.user_email)
    project = find_or_create_project!(config.project_name, user)
    {workflow, trigger, jobs} = find_or_create_workflow!(project, user)
    snapshot = snapshot_for!(workflow)

    dataclips = seed_dataclips(project, config)

    seed_history(%{
      config: config,
      user: user,
      project: project,
      workflow: workflow,
      trigger: trigger,
      jobs: jobs,
      snapshot: snapshot,
      dataclips: dataclips
    })

    fill_search_vectors()
    report(project)
  end

  # ---------------------------------------------------------------- scaffolding

  defp find_user!(email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        raise """
        No user with email #{email}. Pass USER_EMAIL=<an existing user> or run
        `mix run priv/repo/seeds.exs` first.
        """

      user ->
        user
    end
  end

  defp find_or_create_project!(name, user) do
    case Repo.get_by(Lightning.Projects.Project, name: name) do
      nil ->
        log("creating project #{name}")

        {:ok, project} =
          Projects.create_project(
            %{
              name: name,
              # No retention period: the data retention workers must not purge
              # the history we are seeding.
              project_users: [%{user_id: user.id, role: :owner}]
            },
            false
          )

        project

      project ->
        log("reusing project #{name} (#{project.id})")
        project
    end
  end

  defp find_or_create_workflow!(project, user) do
    workflow =
      Repo.get_by(Workflows.Workflow,
        project_id: project.id,
        name: "Load Test Workflow"
      )

    case workflow do
      nil -> create_workflow!(project, user)
      workflow -> load_workflow(workflow)
    end
  end

  defp create_workflow!(project, user) do
    log("creating workflow + trigger + jobs")

    {:ok, workflow} =
      Workflows.save_workflow(
        %{name: "Load Test Workflow", project_id: project.id},
        user
      )

    {:ok, trigger} =
      Workflows.build_trigger(%{type: :webhook, workflow_id: workflow.id})

    jobs =
      for i <- 1..3 do
        {:ok, job} =
          Jobs.create_job(
            %{
              name: "Load Test Job #{i}",
              body: "fn(state => state);",
              adaptor: "@openfn/language-common@latest",
              workflow_id: workflow.id
            },
            user
          )

        job
      end

    [job_1, job_2, job_3] = jobs

    {:ok, _} =
      Workflows.create_edge(
        %{
          workflow_id: workflow.id,
          condition_type: :always,
          source_trigger: trigger,
          target_job: job_1,
          enabled: true
        },
        user
      )

    for {source, target} <- [{job_1, job_2}, {job_2, job_3}] do
      {:ok, _} =
        Workflows.create_edge(
          %{
            workflow_id: workflow.id,
            source_job: source,
            condition_type: :on_job_success,
            target_job: target,
            enabled: true
          },
          user
        )
    end

    {Repo.reload!(workflow), trigger, jobs}
  end

  defp load_workflow(workflow) do
    workflow = Repo.preload(workflow, [:triggers, :jobs])
    {workflow, hd(workflow.triggers), workflow.jobs}
  end

  defp snapshot_for!(workflow) do
    case Snapshot.get_current_for(workflow) do
      nil ->
        {:ok, snapshot} = Snapshot.create(workflow)
        snapshot

      snapshot ->
        snapshot
    end
  end

  # ------------------------------------------------------------------ dataclips

  defp seed_dataclips(project, config) do
    log(
      "inserting #{config.dataclip_pool} dataclips of ~#{config.dataclip_bytes}B"
    )

    now = DateTime.utc_now()

    ids =
      1..config.dataclip_pool
      |> Enum.chunk_every(@dataclip_chunk)
      |> Enum.flat_map(fn chunk ->
        rows =
          Enum.map(chunk, fn i ->
            type = if rem(i, 2) == 0, do: :http_request, else: :step_result

            %{
              id: Ecto.UUID.generate(),
              project_id: project.id,
              type: type,
              body: fat_body(config.dataclip_bytes),
              request: if(type == :http_request, do: request_body(), else: nil),
              inserted_at: now,
              updated_at: now
            }
          end)

        {_, _} = Repo.insert_all(Dataclip, rows)
        progress(List.last(chunk), config.dataclip_pool, "dataclips")
        Enum.map(rows, & &1.id)
      end)

    IO.puts("")
    List.to_tuple(ids)
  end

  # A body that does not compress away to nothing in TOAST storage, so the
  # export really does move the bytes we asked for.
  defp fat_body(bytes) do
    records = max(1, div(bytes, 96))

    %{
      "data" => %{
        "resourceType" => "Bundle",
        "entry" =>
          Enum.map(1..records, fn i ->
            %{
              "id" => rand_string(24),
              "index" => i,
              "patient" => rand_string(16),
              "value" => rand_string(20)
            }
          end)
      }
    }
  end

  defp request_body do
    %{
      "headers" => %{
        "content-type" => "application/json",
        "user-agent" => "seed/1.0",
        "x-request-id" => rand_string(16)
      },
      "method" => "POST",
      "path" => "/i/#{rand_string(12)}"
    }
  end

  defp rand_string(bytes) do
    bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  # -------------------------------------------------------------------- history

  defp seed_history(ctx) do
    %{config: config} = ctx

    log("""
    inserting history: \
    #{config.work_orders} work orders, \
    #{config.work_orders * config.runs_per_wo} runs, \
    #{config.work_orders * config.runs_per_wo * config.steps_per_run} steps, \
    #{config.work_orders * config.runs_per_wo * config.logs_per_run} log lines\
    """)

    base = DateTime.utc_now()
    seconds = config.spread_days * 24 * 60 * 60
    step_seconds = max(1, div(seconds, config.work_orders))
    message = rand_string(config.log_line_bytes)

    1..config.work_orders
    |> Enum.chunk_every(@wo_chunk)
    |> Enum.each(fn chunk ->
      chunk
      |> Enum.map(&build_work_order(&1, ctx, base, step_seconds, message))
      |> insert_batch()

      progress(List.last(chunk), config.work_orders, "work orders")
    end)

    IO.puts("")
  end

  defp build_work_order(index, ctx, base, step_seconds, message) do
    %{config: config, dataclips: dataclips} = ctx

    inserted_at = DateTime.add(base, -index * step_seconds, :second)
    wo_id = Ecto.UUID.generate()
    wo_state = state_for(index)

    work_order = %{
      id: wo_id,
      workflow_id: ctx.workflow.id,
      snapshot_id: ctx.snapshot.id,
      trigger_id: ctx.trigger.id,
      dataclip_id: pick(dataclips, index),
      state: wo_state,
      last_activity: last_activity_for(index, base, inserted_at),
      inserted_at: inserted_at,
      updated_at: inserted_at
    }

    # A rejected work order is one the run limit refused, so it has no run at
    # all — the one shape on this page that has to survive without one.
    runs =
      if wo_state == :rejected do
        []
      else
        wo_state
        |> run_states(config.runs_per_wo)
        |> Enum.with_index(1)
        |> Enum.map(fn {run_state, r} ->
          build_run(work_order, run_state, r, index, ctx, inserted_at, message)
        end)
      end

    %{work_order: work_order, runs: runs}
  end

  defp build_run(work_order, run_state, r, index, ctx, inserted_at, message) do
    %{config: config, jobs: jobs, dataclips: dataclips} = ctx

    run_id = Ecto.UUID.generate()
    run_at = DateTime.add(inserted_at, r, :second)

    finished_at =
      if run_state in @in_flight,
        do: nil,
        else: DateTime.add(run_at, 20, :second)

    {run_error_type, step_reason, step_error_type} =
      failure_for(run_state, index)

    # A run stops at the step that broke, so a failing run has fewer steps than
    # a successful one — and `nil` steps is a run that never reached one at all.
    step_count = step_count_for(run_state, index, config.steps_per_run)

    steps =
      for s <- 1..step_count//1 do
        step_id = Ecto.UUID.generate()
        slot = (index * config.runs_per_wo + r) * config.steps_per_run + s
        job = Enum.at(jobs, rem(s - 1, length(jobs)))
        last? = s == step_count

        %{
          step: %{
            id: step_id,
            job_id: job.id,
            snapshot_id: ctx.snapshot.id,
            input_dataclip_id: pick(dataclips, slot * 2),
            output_dataclip_id: pick(dataclips, slot * 2 + 1),
            exit_reason: if(last?, do: step_reason, else: "success"),
            error_type: if(last?, do: step_error_type),
            started_at: run_at,
            finished_at: DateTime.add(run_at, 5, :second),
            inserted_at: run_at,
            updated_at: run_at
          },
          run_step: %{
            id: Ecto.UUID.generate(),
            run_id: run_id,
            step_id: step_id,
            inserted_at: run_at
          }
        }
      end

    logs =
      for l <- 1..config.logs_per_run, steps != [] do
        %{
          id: Ecto.UUID.generate(),
          run_id: run_id,
          step_id:
            steps |> Enum.at(rem(l, length(steps))) |> get_in([:step, :id]),
          message: "[#{l}] #{message}",
          level: :info,
          source: "R/T",
          timestamp: DateTime.add(run_at, l, :millisecond)
        }
      end

    %{
      run: %{
        id: run_id,
        work_order_id: work_order.id,
        dataclip_id: work_order.dataclip_id,
        starting_trigger_id: ctx.trigger.id,
        snapshot_id: ctx.snapshot.id,
        state: run_state,
        error_type: run_error_type,
        claimed_at: if(run_state != :available, do: run_at),
        started_at: if(run_state != :available, do: run_at),
        finished_at: finished_at,
        priority: :normal,
        queue: "default",
        worker_name: "seed-worker",
        inserted_at: run_at,
        updated_at: run_at
      },
      steps: Enum.map(steps, & &1.step),
      run_steps: Enum.map(steps, & &1.run_step),
      logs: logs
    }
  end

  defp insert_batch(built) do
    work_orders = Enum.map(built, & &1.work_order)
    runs = Enum.flat_map(built, fn b -> Enum.map(b.runs, & &1.run) end)
    steps = Enum.flat_map(built, fn b -> Enum.flat_map(b.runs, & &1.steps) end)

    run_steps =
      Enum.flat_map(built, fn b -> Enum.flat_map(b.runs, & &1.run_steps) end)

    logs = Enum.flat_map(built, fn b -> Enum.flat_map(b.runs, & &1.logs) end)

    Repo.insert_all(WorkOrder, work_orders)
    Repo.insert_all(Run, runs)
    Repo.insert_all(Step, steps)
    Repo.insert_all(RunStep, run_steps)

    logs
    |> Enum.chunk_every(@log_chunk)
    |> Enum.each(&Repo.insert_all(LogLine, &1))
  end

  defp state_for(index), do: Map.get(@wo_states, rem(index, 20), :success)

  # The latest run is the one whose completion set the work order's state, so it
  # carries that state and every run before it is a failed attempt someone
  # retried. With the default RUNS_PER_WO=2 that makes half the history
  # retried-to-success work orders, which is the case the health page's unit
  # exists for: the failed run stays failed and the work order still counts once,
  # as a success.
  defp run_states(wo_state, count) do
    List.duplicate(:failed, count - 1) ++ [latest_run_state(wo_state)]
  end

  defp latest_run_state(:pending), do: :available
  defp latest_run_state(:running), do: :started
  defp latest_run_state(wo_state), do: wo_state

  # Rotated on `div(index, 20)`, not `rem`: the two `:failed` buckets both sit
  # at a fixed `rem(index, 20)`, so anything modulo a factor of 20 would pin
  # each of them to a single type.
  defp failure_for(:failed, index) do
    type = Enum.at(@failed_types, rem(div(index, 20), length(@failed_types)))
    {type, "fail", type}
  end

  defp failure_for(state, _index) do
    Map.get(@failures, state, {nil, "success", nil})
  end

  # A crashed run never reached a step; a failing run stops at the one that
  # broke, which rotates so the signatures name different jobs.
  defp step_count_for(:crashed, _index, _per_run), do: 0

  defp step_count_for(state, _index, per_run) when state in @in_flight,
    do: per_run

  defp step_count_for(state, index, per_run) do
    if state == :success, do: per_run, else: rem(index, per_run) + 1
  end

  # Mostly the same as inserted_at, but every 25th work order was retried
  # recently — the health page's window is measured on last_activity, so these
  # are the rows that show up as today's work however old they are.
  defp last_activity_for(index, base, inserted_at) do
    if rem(index, 25) == 0 do
      DateTime.add(base, -rem(index, 3) * 3600, :second)
    else
      inserted_at
    end
  end

  defp pick(dataclips, i) do
    :erlang.element(rem(i, tuple_size(dataclips)) + 1, dataclips)
  end

  # ------------------------------------------------- full text search vectors

  # log_lines and dataclips are inserted with a NULL search_vector and filled in
  # later by LogLines.SearchVectorWorker / Invocation.DataclipSearchVectorWorker.
  # Bulk-seeding leaves those workers a backlog of hundreds of thousands of rows,
  # and they then compete with the export for the connection pool — which makes
  # any timing taken straight after seeding meaningless. Fill the vectors here so
  # the seeded database looks like one that has caught up.
  defp fill_search_vectors do
    if System.get_env("FILL_SEARCH_VECTORS", "true") == "true" do
      log("filling search vectors (FILL_SEARCH_VECTORS=false to skip)")

      fill_loop(
        """
        WITH pending AS (
          SELECT id, run_id FROM log_lines
          WHERE search_vector IS NULL
          LIMIT 25000 FOR UPDATE SKIP LOCKED
        )
        UPDATE log_lines l
        SET search_vector =
          safe_to_tsvector('public.english_nostop'::regconfig, l.message)
        FROM pending p WHERE l.id = p.id AND l.run_id = p.run_id
        """,
        "log lines"
      )

      fill_loop(
        """
        WITH pending AS (
          SELECT id FROM dataclips
          WHERE search_vector IS NULL
          LIMIT 500 FOR UPDATE SKIP LOCKED
        )
        UPDATE dataclips d
        SET search_vector =
          safe_jsonb_to_tsvector('public.english_nostop'::regconfig, d.body)
        FROM pending p WHERE d.id = p.id
        """,
        "dataclips"
      )

      IO.puts("")
    else
      log("skipping search vector fill; the background workers will catch up")
    end

    :ok
  end

  defp fill_loop(sql, label, total \\ 0) do
    case Repo.query!(sql, [], timeout: :timer.minutes(5)).num_rows do
      0 ->
        :ok

      filled ->
        progress(total + filled, "?", label)
        fill_loop(sql, label, total + filled)
    end
  end

  # ------------------------------------------------------------------ reporting

  defp report(project) do
    %{rows: [row]} =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM work_orders wo
             JOIN workflows w ON w.id = wo.workflow_id WHERE w.project_id = $1),
          (SELECT count(*) FROM runs r JOIN work_orders wo ON wo.id = r.work_order_id
             JOIN workflows w ON w.id = wo.workflow_id WHERE w.project_id = $1),
          (SELECT count(*) FROM steps s JOIN run_steps rs ON rs.step_id = s.id
             JOIN runs r ON r.id = rs.run_id
             JOIN work_orders wo ON wo.id = r.work_order_id
             JOIN workflows w ON w.id = wo.workflow_id WHERE w.project_id = $1),
          (SELECT count(*) FROM log_lines ll JOIN runs r ON r.id = ll.run_id
             JOIN work_orders wo ON wo.id = r.work_order_id
             JOIN workflows w ON w.id = wo.workflow_id WHERE w.project_id = $1),
          (SELECT count(*) FROM dataclips WHERE project_id = $1),
          (SELECT pg_size_pretty(sum(pg_column_size(body))) FROM dataclips WHERE project_id = $1)
        """,
        [Ecto.UUID.dump!(project.id)]
      )

    [wos, runs, steps, logs, dataclips, dataclip_bytes] = row

    log("""
    done. project #{project.name} (#{project.id}) now holds:
      work orders: #{wos}
      runs:        #{runs}
      steps:       #{steps}
      log lines:   #{logs}
      dataclips:   #{dataclips} (#{dataclip_bytes} on disk)

    Now export it from the project's History page and watch the job.
    """)
  end

  defp progress(done, total, label) do
    IO.write("\r  #{label}: #{done}/#{total}")
  end

  defp log(message), do: IO.puts("[seed] #{message}")
end

{elapsed, :ok} = :timer.tc(fn -> ExportLoadSeed.run(ExportLoadSeed.config()) end)
IO.puts("[seed] seeded in #{Float.round(elapsed / 1_000_000, 1)}s")
