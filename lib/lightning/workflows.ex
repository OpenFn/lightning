defmodule Lightning.Workflows do
  @moduledoc """
  The Workflows context.
  """

  import Ecto.Query, warn: false
  alias Quantum.Job
  alias Lightning.Repo
  alias Lightning.Jobs.{Job}
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
    from(w in Workflow,
      join: j in assoc(w, :jobs),
      preload: [jobs: {j, [:credential, :workflow, trigger: [:upstream_job]]}],
      where: w.project_id == ^project.id
    )
    |> Repo.all()
  end

  defp trigger_for_project_space(job) do
    case job.trigger.type do
      :webhook ->
        %{
          "url" =>
            Helpers.webhooks_url(
              LightningWeb.Endpoint,
              :create,
              [job.id]
            )
        }

      :cron ->
        %{"expression" => job.trigger.cron_expression}

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
end
