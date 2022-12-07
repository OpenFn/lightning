defmodule Lightning.AttemptService do
  @moduledoc """
  The Attempts context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}

  @doc """
  Create an attempt

  ## Examples

      iex> create_attempt(%{field: value})
      {:ok, %Attempt{}}

      iex> create_attempt(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_attempt(work_order, job, reason) do
    project_id = job.workflow.project_id
    dataclip_id = reason.dataclip_id

    build_attempt(work_order, reason)
    |> Ecto.Changeset.put_assoc(:runs, [
      Run.changeset(%Run{}, %{
        project_id: project_id,
        job_id: job.id,
        input_dataclip_id: dataclip_id
      })
    ])
    |> Repo.insert()
  end

  def build_attempt(work_order, reason) do
    Ecto.build_assoc(work_order, :attempts)
    |> Ecto.Changeset.change(%{reason: reason})
  end

  @doc """
  Adds an Attempt to an unsaved Run

  When given an Attempt, it simply adds the Run to a new AttemptRun.
  However when given an AttemptRun, the Run (from the AttemptRun) is
  set as the previous Run for the new unsaved Run.
  """
  @spec append(Attempt.t() | AttemptRun.t(), Ecto.Changeset.t(Run.t())) ::
          {:ok, AttemptRun.t()} | {:error, Ecto.Changeset.t(AttemptRun.t())}
  def append(%Attempt{} = attempt, %Ecto.Changeset{} = run) do
    AttemptRun.new()
    |> Ecto.Changeset.put_assoc(:attempt, attempt)
    |> Ecto.Changeset.put_assoc(:run, run)
    |> Repo.insert()
  end

  def append(%AttemptRun{} = attempt_run, %Ecto.Changeset{} = run) do
    AttemptRun.new(%{attempt_id: attempt_run.attempt_id})
    |> Ecto.Changeset.put_assoc(
      :run,
      run |> Ecto.Changeset.put_change(:previous_id, attempt_run.run_id)
    )
    |> Repo.insert()
  end

  @doc """
  Creates a new Attempt starting from a given run.

  All upstream/prior Runs that were performed on that attempt are associated
  with the new Attempt, where as the specified run is used to create a new one
  and is added to the Attempt.

  Any runs downstream from the Run given are ignored.
  """
  @spec retry(
          Attempt.t(),
          Run.t(),
          Ecto.Changeset.t(Lightning.InvocationReason.t())
          | Lightning.InvocationReason.t()
        ) ::
          {:ok, AttemptRun.t()} | {:error, Ecto.Changeset.t(AttemptRun.t())}
  def retry(%Attempt{} = attempt, %Run{} = run, reason) do
    attempt = Repo.preload(attempt, :work_order)

    # get all the jobs for the workflow

    workflow_jobs =
      from(j in Lightning.Jobs.Job,
        join: wf in assoc(j, :workflow),
        join: a in assoc(wf, :attempts),
        where: a.id == ^attempt.id,
        preload: [trigger: :upstream_job]
      )
      |> Repo.all()

    graph =
      Lightning.Workflows.Graph.new(workflow_jobs)
      |> Lightning.Workflows.Graph.remove(run.job_id)

    remaining_jobs = graph.jobs |> Enum.map(& &1.id)

    runs =
      from(r in Run,
        join: a in assoc(r, :attempts),
        where: a.id == ^attempt.id,
        where: r.job_id in ^remaining_jobs
      )
      |> Repo.all()

    build_attempt(attempt.work_order, reason)
    |> Ecto.Changeset.put_assoc(:runs, runs)
    |> Repo.insert!()
    |> append(Run.new_from(run))
  end

  def get_for_rerun(attempt_id, run_id) do
    from(ar in AttemptRun,
      where: ar.attempt_id == ^attempt_id and ar.run_id == ^run_id,
      preload: [
        :attempt,
        run:
          ^from(r in Run,
            select: [
              :id,
              :job_id,
              :started_at,
              :finished_at,
              :exit_code,
              :input_dataclip_id,
              :output_dataclip_id
            ]
          )
      ]
    )
    |> Repo.one()
  end
end
