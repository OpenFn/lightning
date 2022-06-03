defmodule Lightning.Jobs.Query do
  @moduledoc """
  Query module for finding Jobs.
  """
  alias Lightning.Jobs.{Job, Trigger}
  alias Lightning.Projects.Project
  import Ecto.Query

  defmodule Workflow do
    # Used to query downstream jobs while maintaining a 'workflow_id' which
    # is used to keep track of the initiating job.
    @moduledoc false
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: false}
    embedded_schema do
      field :job_id, :binary_id
      field :workflow_id, :binary_id
      field :upstream_job_id, :binary_id
    end
  end

  @doc """
  Find the 'first' Job in a workflow, based on a given Job.
  This query uses a recursive CTE to interate upwards until it finds the
  first Job that has no upstream job.
  """
  def upstream_job_query(%Job{} = job) do
    initial_query = from(t in Trigger, where: t.job_id == ^job.id)

    upstream_recursion_query =
      from(t in Trigger,
        join: w in "workflows",
        on: w.upstream_job_id == t.job_id
      )

    upstream_cte =
      initial_query
      |> union(^upstream_recursion_query)

    {"workflows", Trigger}
    |> recursive_ctes(true)
    |> with_cte("workflows", as: ^upstream_cte)
    |> where([w], is_nil(w.upstream_job_id))
  end

  @doc """
  Find the 'descendants' for a Job in a workflow, based on a given Job.
  This query uses a recursive CTE to interate downwards following the upstream
  job relationship until it can't find any more jobs.
  """
  def downstream_jobs_query(upstream_query) do
    initial_query =
      from(t in Trigger,
        join: uq in subquery(upstream_query),
        on: t.job_id == uq.job_id,
        select: %{id: t.id, job_id: t.job_id, workflow_id: uq.job_id}
      )

    recursion_query =
      from(t in Trigger,
        join: w in "workflows",
        on: w.job_id == t.upstream_job_id,
        select: %{id: t.id, job_id: t.job_id, workflow_id: w.workflow_id}
      )

    downstream_cte =
      initial_query
      |> union(^recursion_query)

    {"workflows", Workflow}
    |> recursive_ctes(true)
    |> with_cte("workflows", as: ^downstream_cte)
    |> select([w], %{id: w.id, job_id: w.job_id, workflow_id: w.workflow_id})
  end

  @doc """
  Find all the initiating jobs for a project, the criteria is that the job
  is not downstream from another job.
  """
  def initiating_jobs_query(%Project{} = project) do
    from(t in Trigger,
      join: j in assoc(t, :job),
      where: is_nil(t.upstream_job_id),
      where: j.project_id == ^project.id,
      select: %{id: t.id, job_id: t.job_id}
    )
  end

  @doc """
  Find all Jobs related to either a Job or a Project.

  When given a Job, we first find the initiating/top job and then
  select all descendants - ensuring that you get sibling jobs as
  well (two or more jobs that rely on the same upstream job).

  When given a Project, we can find all initiating jobs by their lack of an
  upstream job, then find all descendants. In addition a `workflow_id` is
  attached to the query in order to later group workflows by their initiating
  job.
  """
  def workflow_query(%Job{} = job) do
    upstream_job_query(job)
    |> downstream_jobs_query()
  end

  def workflow_query(%Project{} = project) do
    initiating_jobs_query(project)
    |> downstream_jobs_query()
  end
end
