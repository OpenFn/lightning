defmodule LightningWeb.API.HistoryHelpers do
  @moduledoc """
  Builders for the API tests of the routes that start, retry and cancel work
  orders and runs, read a run's steps and export history.
  """
  import Lightning.Factories
  import LightningWeb.ConnHelpers, only: [assign_bearer: 2]
  import Lightning.ServiceAccountHelpers, only: [with_service_account: 2]

  alias Lightning.Repo

  @doc """
  A JSON conn and its callers: an `editor` and a `viewer` of `project`, an
  editor of `mfa_project` (which requires MFA they haven't set up) as
  `short_of_mfa`, a `stranger`, a `superuser` who is no member, and the
  `service_account` holding every grant.
  """
  def history_callers(conn) do
    conn =
      conn
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.put_req_header("content-type", "application/json")

    [editor, viewer, short_of_mfa, stranger] = insert_list(4, :user)

    project =
      insert(:project,
        project_users: [
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    mfa_project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: short_of_mfa, role: :editor}]
      )

    {service_account, _account} =
      with_service_account(conn, Lightning.ServiceAccount.AccessToken.scopes())

    %{
      conn: conn,
      project: project,
      mfa_project: mfa_project,
      editor_user: editor,
      editor: assign_bearer(conn, editor),
      viewer: assign_bearer(conn, viewer),
      short_of_mfa: assign_bearer(conn, short_of_mfa),
      stranger: assign_bearer(conn, stranger),
      superuser: assign_bearer(conn, insert(:user, role: :superuser)),
      service_account: service_account
    }
  end

  @doc """
  A workflow in `project` whose webhook trigger leads to job `a`, then `b`,
  with a snapshot, returned with its trigger and jobs reloaded.
  """
  def runnable_workflow(project, attrs \\ []) do
    job_a = build(:job, name: "a")
    job_b = build(:job, name: "b")
    trigger = build(:trigger, type: :webhook)

    workflow =
      build(:workflow, Keyword.merge([project: project], attrs))
      |> with_job(job_a)
      |> with_job(job_b)
      |> with_trigger(trigger)
      |> with_edge({trigger, job_a})
      |> with_edge({job_a, job_b})
      |> insert()

    {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

    %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: Repo.reload!(trigger),
      job_a: Repo.reload!(job_a),
      job_b: Repo.reload!(job_b)
    }
  end

  @doc """
  A work order of `graph` (from `runnable_workflow/2`) holding one run that
  ran both jobs, each step taking `dataclip`. `run_attrs` go to the run.
  Returns the work order, the run and its steps `a` and `b`.
  """
  def ran_work_order(graph, run_attrs \\ [], dataclip \\ nil) do
    dataclip =
      dataclip || insert(:dataclip, project: graph.workflow.project)

    step_a =
      insert(:step,
        job: graph.job_a,
        input_dataclip: dataclip,
        exit_reason: "success",
        started_at: ~U[2024-01-01 10:00:00.000000Z],
        finished_at: ~U[2024-01-01 10:00:01.000000Z],
        inserted_at: ~U[2024-01-01 10:00:00.000000Z]
      )

    step_b =
      insert(:step,
        job: graph.job_b,
        input_dataclip: dataclip,
        exit_reason: "fail",
        error_type: "RuntimeError",
        started_at: ~U[2024-01-01 10:00:02.000000Z],
        finished_at: ~U[2024-01-01 10:00:03.000000Z],
        inserted_at: ~U[2024-01-01 10:00:02.000000Z]
      )

    work_order =
      insert(:workorder,
        workflow: graph.workflow,
        snapshot: graph.snapshot,
        trigger: graph.trigger,
        dataclip: dataclip,
        state: :failed,
        runs: [
          Map.merge(
            %{
              state: :failed,
              dataclip: dataclip,
              snapshot: graph.snapshot,
              starting_trigger: graph.trigger,
              steps: [step_a, step_b]
            },
            Map.new(run_attrs)
          )
        ]
      )

    %{
      work_order: work_order,
      run: hd(work_order.runs),
      step_a: step_a,
      step_b: step_b
    }
  end

  @doc """
  A work order of `graph` whose one run waits for a worker (`available`), or
  is in `run_state`. Other `attrs` go to the work order.
  """
  def pending_work_order(graph, attrs \\ []) do
    {run_state, attrs} = Keyword.pop(attrs, :run_state, :available)
    dataclip = insert(:dataclip, project: graph.workflow.project)

    insert(
      :workorder,
      Keyword.merge(
        [
          workflow: graph.workflow,
          snapshot: graph.snapshot,
          trigger: graph.trigger,
          dataclip: dataclip,
          state: :pending,
          runs: [
            %{
              state: run_state,
              dataclip: dataclip,
              snapshot: graph.snapshot,
              starting_trigger: graph.trigger
            }
          ]
        ],
        attrs
      )
    )
  end

  @doc """
  Stubs the usage limiter to refuse new runs with `reason`.
  """
  def limit_runs(reason) do
    Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
      %{type: :new_run}, _context ->
        {:error, reason,
         %Lightning.Extensions.Message{text: "Upgrade for more runs"}}

      _action, _context ->
        :ok
    end)
  end

  @doc """
  The limiter refusals of new runs, each with the status and code the API
  answers it: the two the limiter type names, and one it doesn't.
  """
  def run_limit_refusals do
    [
      {:too_many_runs, 429, :too_many_runs},
      {:runs_hard_limit, 402, :exceeds_limit},
      {:over_the_plan, 402, :exceeds_limit}
    ]
  end
end
