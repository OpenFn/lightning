defmodule Lightning.Workflows do
  @moduledoc """
  The Workflows context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias LightningWeb.Router.Helpers
  alias Lightning.Workflows.Workflow
  alias Lightning.Projects.Project

  @doc """
  Returns the list of workflows.

  ## Examples

      iex> list_workflows()
      [%Workflow{}, ...]

  """
  def list_workflows do
    Repo.all(Workflow)
  end

  @doc """
  Gets a single workflow.

  Raises `Ecto.NoResultsError` if the Workflow does not exist.

  ## Examples

      iex> get_workflow!(123)
      %Workflow{}

      iex> get_workflow!(456)
      ** (Ecto.NoResultsError)

  """
  def get_workflow!(id), do: Repo.get!(Workflow, id)

  def get_workflow(id), do: Repo.get(Workflow, id)

  @doc """
  Creates a workflow.

  ## Examples

      iex> create_workflow(%{field: value})
      {:ok, %Workflow{}}

      iex> create_workflow(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_workflow(attrs \\ %{}) do
    %Workflow{}
    |> Workflow.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a workflow.

  ## Examples

      iex> update_workflow(workflow, %{field: new_value})
      {:ok, %Workflow{}}

      iex> update_workflow(workflow, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_workflow(%Workflow{} = workflow, attrs) do
    workflow
    |> Workflow.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a workflow.

  ## Examples

      iex> delete_workflow(workflow)
      {:ok, %Workflow{}}

      iex> delete_workflow(workflow)
      {:error, %Ecto.Changeset{}}

  """
  def delete_workflow(%Workflow{} = workflow) do
    Repo.delete(workflow)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking workflow changes.

  ## Examples

      iex> change_workflow(workflow)
      %Ecto.Changeset{data: %Workflow{}}

  """
  def change_workflow(%Workflow{} = workflow, attrs \\ %{}) do
    Workflow.changeset(workflow, attrs)
  end

  @doc """
  Retrieves a list of Workflows with their jobs and triggers preloaded.
  """
  @spec get_workflows_for(Project.t()) :: [Workflow.t()]
  def get_workflows_for(%Project{} = project) do
    get_workflows_for_query(project)
    |> Repo.all()
  end

  def get_workflows_for_query(%Project{} = project) do
    from(w in Workflow,
      preload: [jobs: [:credential, :workflow, trigger: [:upstream_job]]],
      where: is_nil(w.deleted_at) and w.project_id == ^project.id,
      order_by: [asc: w.name]
    )
  end

  defp trigger_for_project_space(job) do
    case job.trigger.type do
      :webhook ->
        %{
          "webhookUrl" =>
            Helpers.webhooks_url(
              LightningWeb.Endpoint,
              :create,
              [job.trigger.id]
            )
        }

      :cron ->
        %{"cronExpression" => job.trigger.cron_expression}

      type when type in [:on_job_failure, :on_job_success] ->
        %{"upstreamJob" => job.trigger.upstream_job_id}
    end
    |> Enum.into(%{
      "type" => job.trigger.type
    })
  end

  @spec to_project_space([Workflow.t()]) :: %{}
  def to_project_space(workflows) when is_list(workflows) do
    %{
      "jobs" =>
        workflows
        |> Enum.flat_map(fn w -> w.jobs end)
        |> Enum.map(fn job ->
          %{
            "id" => job.id,
            "name" => job.name,
            "adaptor" => job.adaptor,
            "workflowId" => job.workflow_id,
            "trigger" => trigger_for_project_space(job)
          }
        end),
      "workflows" =>
        workflows
        |> Enum.map(fn w -> %{"id" => w.id, "name" => w.name} end)
    }
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the workflow request_deletion.

  ## Examples

      iex> change_request_deletion(workflow)
      %Ecto.Changeset{data: %Workflow{}}

  """
  def mark_for_deletion(workflow, _attrs \\ %{}) do
    workflow_jobs_query =
      from(j in Lightning.Jobs.Job,
        where: j.workflow_id == ^workflow.id
      )

    Repo.transaction(fn ->
      Workflow.request_deletion_changeset(workflow, %{
        "deleted_at" => DateTime.utc_now()
      })
      |> Repo.update()

      Repo.update_all(workflow_jobs_query, set: [enabled: false])
    end)
  end

  defp get_last_run(workorder) do
    List.last(List.first(workorder.attempts |> Repo.preload(:runs)).runs)
  end

  defp has_failed_run?(workorder) do
    workorder.attempts
    |> Repo.preload(:runs)
    |> Enum.map(fn attempt -> attempt.runs end)
    |> List.flatten()
    |> Enum.any?(fn run -> run.exit_code > 0 end)
  end

  def get_digest_data(workflow, digest) do
    digest_timestamp = %{
      daily: Timex.now() |> Timex.to_unix(),
      weekly: Timex.now() |> Timex.shift(days: -7) |> Timex.to_unix(),
      monthly: Timex.now() |> Timex.shift(months: -1) |> Timex.to_unix()
    }

    successful_workorders =
      workflow.work_orders
      |> Enum.filter(fn workorder ->
        last_run = get_last_run(workorder |> Repo.preload(:attempts))

        last_run.exit_code == 0 and
          Timex.to_unix(Timex.now()) - Timex.to_unix(last_run.finished_at) <=
            digest_timestamp[digest]
      end)
      |> length()

    rerun_workorders =
      workflow.work_orders
      |> Enum.filter(fn workorder ->
        attempts = (workorder |> Repo.preload(:attempts)).attempts |> length()
        last_run = get_last_run(workorder |> Repo.preload(:attempts))

        last_run.exit_code == 0 and
          has_failed_run?(workorder |> Repo.preload(:attempts)) and
          attempts > 1 and
          Timex.to_unix(Timex.now()) - Timex.to_unix(last_run.finished_at) <=
            digest_timestamp[digest]
      end)
      |> length()

    failed_workorders =
      workflow.work_orders
      |> Enum.filter(fn workorder ->
        last_run = get_last_run(workorder |> Repo.preload(:attempts))

        last_run.exit_code > 0 and
          Timex.to_unix(Timex.now()) - Timex.to_unix(last_run.finished_at) <=
            digest_timestamp[digest]
      end)
      |> length()

    %{
      workflow_name: workflow.name,
      successful_workorders: successful_workorders,
      rerun_workorders: rerun_workorders,
      failed_workorders: failed_workorders
    }
  end
end
