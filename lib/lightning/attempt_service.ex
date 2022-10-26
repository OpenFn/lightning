defmodule Lightning.AttemptService do
  @moduledoc """
  The Attempts context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}

  @doc """
  Creates a reason.

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
end
