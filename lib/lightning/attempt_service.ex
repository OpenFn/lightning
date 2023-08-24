defmodule Lightning.AttemptService do
  @moduledoc """
  The Attempts context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Lightning.Repo
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}
  alias Lightning.InvocationReason

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
        ) :: Ecto.Multi.t()
  def retry(%Attempt{} = attempt, %Run{} = run, reason) do
    attempt = Repo.preload(attempt, :work_order)

    # no way we don't have a workflow , throw if we dont have one
    attempt_workflow = get_workflow_for(attempt) |> Repo.one!()

    existing_runs =
      from(r in Run,
        join: a in assoc(r, :attempts),
        where: a.id == ^attempt.id
      )
      |> Repo.all()

    {skipped_runs, new_run} =
      calculate_runs(attempt_workflow, existing_runs, run)

    Multi.new()
    |> Multi.insert(:attempt, fn _ ->
      build_attempt(attempt.work_order, reason)
      |> Ecto.Changeset.put_assoc(
        :runs,
        skipped_runs
      )
    end)
    |> Multi.insert(:attempt_run, fn %{attempt: attempt} ->
      AttemptRun.new()
      |> Ecto.Changeset.put_assoc(:attempt, attempt)
      |> Ecto.Changeset.put_assoc(:run, new_run)
    end)
  end

  @doc """
  Creates new Attempts for each pair of corresponding AttemptRun and
  InvocationReason.
  """
  @spec retry_many([AttemptRun.t()], [Lightning.InvocationReason.t()]) ::
          Ecto.Multi.t()
  def retry_many(
        [%AttemptRun{} | _other_runs] = attempt_runs,
        [%InvocationReason{} | _other_reasons] = reasons
      ) do
    attempt_runs =
      attempt_runs
      |> Repo.preload([
        :run,
        attempt: [work_order: [workflow: [:jobs, :edges]], runs: []]
      ])

    Multi.new()
    |> Multi.insert_all(
      :attempts,
      Attempt,
      fn _ ->
        reasons_map = Map.new(reasons, &{&1.run_id, &1.id})
        now = DateTime.utc_now()

        Enum.map(attempt_runs, fn %{attempt: %{work_order: work_order}, run: run} ->
          %{
            work_order_id: work_order.id,
            reason_id: Map.fetch!(reasons_map, run.id),
            inserted_at: now
          }
        end)
      end,
      returning: true
    )
    |> Multi.run(:attempt_runs_setup, fn _repo,
                                         %{attempts: {_count, attempts}} ->
      attempts_map = Map.new(attempts, &{&1.work_order_id, &1.id})
      now = DateTime.utc_now()

      setup =
        attempt_runs
        |> Enum.map(fn %{attempt: attempt, run: run} ->
          {skipped_runs, new_run} =
            calculate_runs(attempt.work_order.workflow, attempt.runs, run)

          attempt_id = attempts_map[attempt.work_order.id]

          skipped_attempt_runs =
            attempt_runs_attrs(attempt_id, skipped_runs, now)

          {attempt_id, {skipped_attempt_runs, new_run.changes}}
        end)

      {:ok, setup}
    end)
    |> Multi.insert_all(
      :skipped_attempt_runs,
      AttemptRun,
      fn %{attempt_runs_setup: setup} ->
        Enum.flat_map(setup, fn {_, {skipped_runs, _new_run}} ->
          skipped_runs
        end)
      end
    )
    |> Multi.insert_all(
      :runs,
      Run,
      fn %{attempt_runs_setup: setup} ->
        now = DateTime.utc_now()

        Enum.map(setup, fn {_, {_skipped_runs, new_run}} ->
          Map.merge(new_run, %{inserted_at: now, updated_at: now})
        end)
      end,
      returning: true
    )
    |> Multi.insert_all(
      :attempt_runs,
      AttemptRun,
      fn %{attempt_runs_setup: setup} ->
        now = DateTime.utc_now()

        Enum.flat_map(setup, fn {attempt_id, {_skipped_runs, new_run}} ->
          attempt_runs_attrs(attempt_id, [new_run], now)
        end)
      end,
      returning: true
    )
  end

  def retry_many([], []) do
    Multi.new()
  end

  defp attempt_runs_attrs(attempt_id, runs, timestamp) do
    Enum.map(runs, fn run ->
      %{
        attempt_id: attempt_id,
        run_id: run.id,
        inserted_at: timestamp
      }
    end)
  end

  def get_workflow_for(%Attempt{work_order: %{workflow_id: wid}}) do
    from(w in Lightning.Workflows.Workflow,
      where: w.id == ^wid,
      preload: [:jobs, edges: [:target_job, :source_job]]
    )
  end

  def calculate_runs(workflow, existing_runs, starting_run) do
    # TODO sanity check that ALL existing runs have a place in the graph

    runs_by_job_id =
      existing_runs
      |> Enum.into(%{}, fn %Run{job_id: job_id} = run -> {job_id, run} end)

    graph =
      Lightning.Workflows.Graph.new(workflow)
      |> Lightning.Workflows.Graph.remove(starting_run.job_id)

    {graph.jobs
     |> Enum.map(fn %{id: id} -> runs_by_job_id[id] end)
     |> Enum.reject(&is_nil/1), Run.new_from(starting_run)}
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

  @doc """
  Returns a list of AttemptRun structs that should be rerun for the given list
  of work order ids.
  """
  @spec list_for_rerun_from_start([Ecto.UUID.t()]) :: [AttemptRun.t()]
  def list_for_rerun_from_start(order_ids) when is_list(order_ids) do
    attempt_run_numbers_query =
      from(ar in AttemptRun,
        join: att in assoc(ar, :attempt),
        join: r in assoc(ar, :run),
        where: att.work_order_id in ^order_ids,
        select: %{
          id: ar.id,
          row_num:
            row_number()
            |> over(
              partition_by: att.work_order_id,
              order_by: coalesce(r.started_at, r.inserted_at)
            )
        }
      )

    first_attempt_runs_query =
      from(ar in AttemptRun,
        join: arn in subquery(attempt_run_numbers_query),
        on: ar.id == arn.id,
        join: att in assoc(ar, :attempt),
        join: wo in assoc(att, :work_order),
        where: arn.row_num == 1,
        order_by: [asc: wo.inserted_at],
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

    Repo.all(first_attempt_runs_query)
  end

  @doc """
  Returns a list of AttemptRun structs that should be rerun for the given list
  of workorder ids that are associated to the given Job
  """
  @spec list_for_rerun_from_job(
          workorders :: [Ecto.UUID.t(), ...],
          job_id :: Ecto.UUID.t()
        ) :: [
          AttemptRun.t(),
          ...
        ]
  def list_for_rerun_from_job(order_ids, job_id)
      when is_list(order_ids) do
    last_attempts_query =
      from(att in Lightning.Attempt,
        join: r in assoc(att, :runs),
        where: att.work_order_id in ^order_ids,
        group_by: att.work_order_id,
        select: %{
          work_order_id: att.work_order_id,
          last_inserted_at: max(att.inserted_at)
        }
      )

    attempt_runs_query =
      from(ar in AttemptRun,
        join: att in assoc(ar, :attempt),
        join: wo in assoc(att, :work_order),
        join: last in subquery(last_attempts_query),
        on:
          last.work_order_id == att.work_order_id and
            att.inserted_at == last.last_inserted_at,
        join: r in assoc(ar, :run),
        on: r.job_id == ^job_id,
        order_by: [asc: wo.inserted_at],
        preload: [
          attempt: att,
          run: r
        ]
      )

    Repo.all(attempt_runs_query)
  end

  @doc """
  Get the latest attempt associated to a given run
  """

  def get_last_attempt_for(%Run{id: id}) do
    from(a in Attempt,
      join: r in assoc(a, :runs),
      where: r.id == ^id,
      order_by: [desc: a.inserted_at],
      limit: 1,
      preload: [work_order: :workflow]
    )
    |> Repo.one()
  end
end
