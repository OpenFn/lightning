defmodule Lightning.WorkOrderService do
  @moduledoc """
  The WorkOrderService.
  """

  import Ecto.Query, warn: false

  alias Lightning.Repo

  alias Lightning.{
    WorkOrder,
    InvocationReason,
    InvocationReasons,
    Attempt,
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

  def create_webhook_workorder(edge, dataclip_body) do
    multi_for(:webhook, edge, dataclip_body)
    |> Multi.run(:attempt, fn _repo, models ->
      AttemptService.build_attempt(models.work_order, models.reason)
      |> Lightning.Attempts.enqueue()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, models} ->
        job = edge.target_job |> Repo.preload(:workflow)

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
        Pipeline.new(%{attempt_run_id: models.attempt_run.id})
        |> Pipeline.enqueue()

        broadcast(
          models.job.workflow.project_id,
          %Events.AttemptCreated{attempt: models.attempt}
        )

        {:ok, models}

      any ->
        any
    end
  end

  @spec retry_attempt_run(AttemptRun.t(), User.t()) ::
          {:ok, %{attempt_run: AttemptRun.t(), attempt: Attempt.t()}}
  def retry_attempt_run(attempt_run, user) do
    multi =
      attempt_run
      |> Repo.preload([:attempt, :run])
      |> multi_for_retry_attempt_run(user)

    with {:ok, %{attempt_run: attempt_run, attempt: attempt} = changes} <-
           Repo.transaction(multi) do
      Pipeline.new(%{attempt_run_id: attempt_run.id})
      |> Pipeline.enqueue()

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
    end
  end

  def retry_attempt_runs(attempt_runs, user) when is_list(attempt_runs) do
    multi =
      Multi.new()
      |> Multi.insert_all(
        :reasons,
        InvocationReason,
        fn _changes ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          Enum.map(attempt_runs, fn %{run_id: run_id} ->
            %{
              type: :retry,
              run_id: run_id,
              user_id: user.id,
              inserted_at: now,
              updated_at: now
            }
          end)
        end,
        returning: true
      )
      |> Multi.merge(fn %{reasons: {_count, reasons}} ->
        AttemptService.retry_many(attempt_runs, reasons)
      end)

    with {:ok, %{attempt_runs: {_count, attempt_runs}} = changes} <-
           Repo.transaction(multi) do
      Enum.map(attempt_runs, fn attempt_run ->
        Pipeline.new(%{attempt_run_id: attempt_run.id})
      end)
      |> Pipeline.enqueue()

      {:ok, changes}
    end
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
          Lightning.Workflows.Edge.t(),
          Ecto.Changeset.t(Dataclip.t())
          | Dataclip.t()
          | %{optional(String.t()) => any}
        ) :: Ecto.Multi.t()
  def multi_for(
        type,
        %Lightning.Workflows.Edge{target_job: job, source_trigger: trigger},
        dataclip_body
      )
      when type in [:webhook, :cron] do
    Multi.new()
    |> put_job(job)
    |> put_dataclip(dataclip_body)
    |> Multi.insert(:reason, fn %{dataclip: dataclip} ->
      InvocationReasons.build(trigger, dataclip)
    end)
    |> Multi.insert(:work_order, fn %{reason: reason, job: job} ->
      build(job.workflow, reason)
    end)

    # ----- snip ----
    # this is where the attempt is created
    # for pipeline, inserted as claimed
    # but must have an attempt run to be claimed
    # |> Multi.insert(:attempt, fn %{work_order: work_order, reason: reason} ->
    #   AttemptService.build_attempt(work_order, reason)
    # end)
    # |> Multi.insert(:attempt_run, fn %{
    #                                    attempt: attempt,
    #                                    dataclip: dataclip,
    #                                    job: job
    #                                  } ->
    #   AttemptRun.new(
    #     attempt,
    #     Run.new(%{
    #       job_id: job.id,
    #       input_dataclip_id: dataclip.id
    #     })
    #   )
    # end)
  end

  defp put_job(multi, job) do
    multi |> Multi.put(:job, Repo.preload(job, [:workflow]))
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
    |> Repo.insert(returning: true)
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
