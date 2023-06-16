defmodule Lightning.WorkOrderService do
  @moduledoc """
  The WorkOrderService.
  """

  import Ecto.Query, warn: false

  alias Lightning.Repo

  alias Lightning.{
    WorkOrder,
    InvocationReasons,
    AttemptRun,
    AttemptService,
    Pipeline
  }

  alias Lightning.Workorders.Events

  alias Lightning.Invocation.{Dataclip, Run}
  alias Lightning.Accounts.User
  alias Lightning.Jobs.Job

  alias Ecto.Multi

  @pubsub Lightning.PubSub

  def create_webhook_workorder(job, dataclip_body) do
    multi_for(:webhook, job, dataclip_body)
    |> Repo.transaction()
    |> case do
      {:ok, models} ->
        Pipeline.new(%{attempt_run_id: models.attempt_run.id})
        |> Oban.insert()

        job = job |> Repo.preload(:workflow)

        broadcast(
          job.workflow.project_id,
          %Events.AttemptCreated{attempt: models.attempt}
        )

        {:ok, models}

      any ->
        any
    end
  end

  def create_manual_workorder(job, dataclip, user) do
    multi_for_manual(job, dataclip, user)
    |> Repo.transaction()
    |> case do
      {:ok, models} ->
        Lightning.Pipeline.new(%{attempt_run_id: models.attempt_run.id})
        |> Oban.insert()

        broadcast(
          job.workflow.project_id,
          %Events.AttemptCreated{attempt: models.attempt}
        )

        {:ok, models}

      any ->
        any
    end
  end

  # @spec retry_attempt_run(AttemptRun.t(), User.t()) :: Ecto.Multi.t()
  def retry_attempt_run(attempt_run, user) do
    attempt_run
    |> Repo.preload([:attempt, :run])
    |> multi_for_retry_attempt_run(user)
    |> Repo.transaction()
    |> case do
      {:ok, %{attempt_run: attempt_run, attempt: attempt} = changes} ->
        Pipeline.new(%{attempt_run_id: attempt_run.id})
        |> Oban.insert()

        project_id =
          from(r in Run,
            join: j in assoc(r, :job),
            join: p in assoc(j, :project),
            where: r.id == ^attempt_run.run_id,
            select: [p.id]
          )
          |> Repo.one!()

        broadcast(project_id, %Events.AttemptCreated{attempt: attempt})
        {:ok, changes}

      other ->
        other
    end
  end

  def retry_attempt_runs(attempt_runs, user) when is_list(attempt_runs) do
    attempt_runs
    |> Repo.preload([:attempt, run: [job: :workflow]])
    |> Enum.reduce(Multi.new(), fn attempt_run, multi ->
      Multi.run(multi, "retry.#{attempt_run.id}", fn _repo, _changes ->
        attempt_run
        |> multi_for_retry_attempt_run(user)
        |> Oban.insert(:run, fn %{attempt_run: attempt_run} ->
          Pipeline.new(%{attempt_run_id: attempt_run.id})
        end)
        |> Multi.run(:broadcast, fn _repo, %{attempt: attempt} ->
          project_id = attempt_run.run.job.workflow.project_id
          broadcast(project_id, %Events.AttemptCreated{attempt: attempt})
          {:ok, nil}
        end)
        |> Repo.transaction()
        |> case do
          {:error, failed_operation, failed_value, changes_so_far} ->
            {:error,
             %{
               failed_operation: failed_operation,
               failed_value: failed_value,
               changes_so_far: changes_so_far
             }}

          other ->
            other
        end
      end)
    end)
    |> Repo.transaction()
  end

  defp multi_for_retry_attempt_run(
         %{attempt: attempt, run: run} = _attempt_run,
         user
       ) do
    Multi.new()
    |> Multi.insert(:reason, fn _ ->
      Lightning.InvocationReasons.build(:retry, %{user: user, run: run})
    end)
    |> Multi.merge(fn %{reason: reason} ->
      AttemptService.retry(attempt, run, reason)
    end)
  end

  @spec multi_for_manual(Job.t(), Dataclip.t(), User.t()) :: Ecto.Multi.t()
  def multi_for_manual(job, dataclip, user) do
    Multi.new()
    |> put_job(job)
    |> put_dataclip(dataclip)
    |> Multi.insert(:reason, fn %{dataclip: dataclip} ->
      InvocationReasons.build(:manual, %{user: user, dataclip: dataclip})
    end)
    |> Multi.insert(:work_order, fn %{reason: reason, job: job} ->
      build(job.workflow, reason)
    end)
    |> Multi.insert(:attempt, fn %{work_order: work_order, reason: reason} ->
      AttemptService.build_attempt(work_order, reason)
    end)
    |> Multi.insert(:attempt_run, fn %{
                                       attempt: attempt,
                                       dataclip: dataclip,
                                       job: job
                                     } ->
      AttemptRun.new(
        attempt,
        Run.new(%{job_id: job.id, input_dataclip_id: dataclip.id})
      )
    end)
  end

  @spec multi_for(
          :webhook | :cron,
          Lightning.Jobs.Job.t(),
          Ecto.Changeset.t(Dataclip.t())
          | Dataclip.t()
          | %{optional(String.t()) => any}
        ) :: Ecto.Multi.t()
  def multi_for(type, job, dataclip_body) when type in [:webhook, :cron] do
    Multi.new()
    |> put_job(job)
    |> put_dataclip(dataclip_body)
    |> Multi.insert(:reason, fn %{dataclip: dataclip, job: job} ->
      InvocationReasons.build(job.trigger, dataclip)
    end)
    |> Multi.insert(:work_order, fn %{reason: reason, job: job} ->
      build(job.workflow, reason)
    end)
    |> Multi.insert(:attempt, fn %{work_order: work_order, reason: reason} ->
      AttemptService.build_attempt(work_order, reason)
    end)
    |> Multi.insert(:attempt_run, fn %{
                                       attempt: attempt,
                                       dataclip: dataclip,
                                       job: job
                                     } ->
      AttemptRun.new(
        attempt,
        Run.new(%{
          job_id: job.id,
          input_dataclip_id: dataclip.id
        })
      )
    end)
  end

  defp put_job(multi, job) do
    multi |> Multi.put(:job, Repo.preload(job, [:trigger, :workflow]))
  end

  defp put_dataclip(multi, %Dataclip{} = dataclip) do
    multi |> Multi.put(:dataclip, dataclip)
  end

  defp put_dataclip(multi, %Ecto.Changeset{} = changeset) do
    multi |> Multi.insert(:dataclip, changeset)
  end

  defp put_dataclip(multi, dataclip_body) when is_map(dataclip_body) do
    multi
    |> Multi.insert(
      :dataclip,
      fn %{job: job} ->
        Dataclip.new(%{
          type: :http_request,
          body: dataclip_body,
          project_id: job.workflow.project_id
        })
      end
    )
  end

  @doc """
  Creates a work_order.

  ## Examples

      iex> create_work_order(%{field: value})
      {:ok, %WorkOrder{}}

      iex> create_work_order(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_work_order(attrs \\ %{}) do
    %WorkOrder{}
    |> WorkOrder.changeset(attrs)
    |> Repo.insert()
  end

  def build(workflow, reason) do
    WorkOrder.new()
    |> Ecto.Changeset.put_assoc(:workflow, workflow)
    |> Ecto.Changeset.put_assoc(:reason, reason)
  end

  def attempt_updated(%Run{} = run) do
    run = run |> Repo.preload([:attempts, job: :workflow])

    for attempt <- run.attempts do
      broadcast(
        run.job.workflow.project_id,
        %Events.AttemptUpdated{attempt: attempt}
      )
    end
  end

  def subscribe(project_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(project_id))
  end

  defp broadcast(project_id, msg) do
    Phoenix.PubSub.broadcast(@pubsub, topic(project_id), {__MODULE__, msg})
  end

  defp topic(project_id), do: "project:#{project_id}"
end
