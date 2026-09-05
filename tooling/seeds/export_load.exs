# Seeds the dev database with a large work order history, so the
# Lightning.WorkOrders.ExportWorker DBConnection timeout can be reproduced
# locally.
#
#     mix run tooling/seeds/export_load.exs
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
    %{config: config, jobs: jobs, dataclips: dataclips} = ctx

    inserted_at = DateTime.add(base, -index * step_seconds, :second)
    wo_id = Ecto.UUID.generate()

    work_order = %{
      id: wo_id,
      workflow_id: ctx.workflow.id,
      snapshot_id: ctx.snapshot.id,
      trigger_id: ctx.trigger.id,
      dataclip_id: pick(dataclips, index),
      state: state_for(index),
      last_activity: inserted_at,
      inserted_at: inserted_at,
      updated_at: inserted_at
    }

    runs =
      for r <- 1..config.runs_per_wo do
        run_id = Ecto.UUID.generate()
        run_at = DateTime.add(inserted_at, r, :second)

        steps =
          for s <- 1..config.steps_per_run do
            step_id = Ecto.UUID.generate()
            slot = (index * config.runs_per_wo + r) * config.steps_per_run + s
            job = Enum.at(jobs, rem(s - 1, length(jobs)))

            %{
              step: %{
                id: step_id,
                job_id: job.id,
                snapshot_id: ctx.snapshot.id,
                input_dataclip_id: pick(dataclips, slot * 2),
                output_dataclip_id: pick(dataclips, slot * 2 + 1),
                exit_reason: "success",
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
          for l <- 1..config.logs_per_run do
            %{
              id: Ecto.UUID.generate(),
              run_id: run_id,
              step_id:
                steps
                |> Enum.at(rem(l, config.steps_per_run))
                |> get_in([:step, :id]),
              message: "[#{l}] #{message}",
              level: :info,
              source: "R/T",
              timestamp: DateTime.add(run_at, l, :millisecond)
            }
          end

        %{
          run: %{
            id: run_id,
            work_order_id: wo_id,
            dataclip_id: work_order.dataclip_id,
            starting_trigger_id: ctx.trigger.id,
            snapshot_id: ctx.snapshot.id,
            state: run_state_for(work_order.state),
            claimed_at: run_at,
            started_at: run_at,
            finished_at: DateTime.add(run_at, 20, :second),
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

    %{work_order: work_order, runs: runs}
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

  # A realistic-ish mix: mostly success, some failures and a few still running.
  defp state_for(index) do
    case rem(index, 10) do
      0 -> :failed
      1 -> :crashed
      2 -> :running
      _ -> :success
    end
  end

  defp run_state_for(:running), do: :started
  defp run_state_for(:crashed), do: :crashed
  defp run_state_for(:failed), do: :failed
  defp run_state_for(_), do: :success

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
