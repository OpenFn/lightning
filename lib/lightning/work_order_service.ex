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
  alias Lightning.Jobs.{Job, Trigger}
  alias Lightning.Workflows.Edge

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
      jobs =
        Enum.map(attempt_runs, fn attempt_run ->
          Pipeline.new(%{attempt_run_id: attempt_run.id})
        end)

      Oban.insert_all(jobs)

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
          Lightning.Jobs.Job.t(),
          Ecto.Changeset.t(Dataclip.t())
          | Dataclip.t()
          | %{optional(String.t()) => any}
        ) :: Ecto.Multi.t()
  #  InvocationReasons.build(job.trigger, dataclip)

  # 1,2,3 ==================================================================

  # --JOB TO JOB------------------------------------------------------------

  # 1 - "flow" and this replacing "on_job_success" or "on_job_fail" triggers
  # with EDGES that go between { source_job_id, condition, target_job_id }

  # --TRIGGER TO JOB--------------------------------------------------------

  # 2 - "cron" - replace job.trigger_id (where trigger.type = cron)
  # with { source_trigger_id, condition, target_job_id }

  # 3 - "webhook" - replace job.trigger_id (where trigger.type = webhook)
  # with { source_trigger_id, condition, target_job_id }

  # ========================================================================

  # build trigger
  # build edge connecting trigger to job

  def multi_for(type, job, dataclip_body) when type in [:webhook, :cron] do
    Multi.new()
    |> put_job(job)
    |> put_dataclip(dataclip_body)
    |> put_trigger(type)
    |> put_edge()
    |> Multi.insert(:reason, fn %{dataclip: dataclip, trigger: trigger} ->
      InvocationReasons.build(trigger, dataclip)
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

  defp put_trigger(multi, type) do
    multi
    |> Multi.insert(
      :trigger,
      fn %{job: %{workflow: workflow}} ->
        Trigger.new(%{
          type: type,
          workflow_id: workflow.id
        })
      end
    )
  end

  defp put_edge(multi) do
    multi
    |> Multi.insert(
      :edge,
      fn %{job: job, trigger: trigger} ->
        Edge.new(%{
          source_trigger_id: trigger.id,
          target_job_id: job.id,
          condition: :always,
          workflow_id: job.workflow.id
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
