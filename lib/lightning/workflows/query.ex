defmodule Lightning.Workflows.Query do
  @moduledoc """
  Query module for finding Jobs.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Step
  alias Lightning.Projects.Project
  alias Lightning.Run
  alias Lightning.WorkOrder
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow

  @doc """
  Returns all jobs accessible to a user, via their projects
  or all jobs in a given project.
  """
  @spec jobs_for(User.t()) :: Ecto.Queryable.t()
  def jobs_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(j in Job,
      join: w in assoc(j, :workflow),
      where: w.project_id in subquery(projects)
    )
  end

  @spec jobs_for(Project.t()) :: Ecto.Queryable.t()
  def jobs_for(%Project{} = project) do
    Ecto.assoc(project, [:workflows, :jobs])
  end

  @doc """
  Returns active jobs with their cron triggers for use in the cron scheduling
  service.
  """
  @spec enabled_cron_jobs_by_edge() :: Ecto.Queryable.t()
  def enabled_cron_jobs_by_edge do
    from(e in Edge,
      join: j in assoc(e, :target_job),
      join: t in assoc(e, :source_trigger),
      where: t.type == :cron and t.enabled,
      preload: [:source_trigger, [target_job: :workflow]]
    )
  end

  @doc """
  Returns snapshots that are no longer being used by any workflow, work order, run, or step.

  A snapshot is considered unused if:
  - It's not the current version of any workflow (lock_version doesn't match workflow's lock_version)
  - It's not referenced by any work order
  - It's not referenced by any run
  - It's not referenced by any step
  """
  @spec unused_snapshots() :: Ecto.Queryable.t()
  def unused_snapshots do
    from(ws in Snapshot,
      as: :snapshot,
      where:
        not exists(
          from(w in Workflow,
            where:
              w.id == parent_as(:snapshot).workflow_id and
                parent_as(:snapshot).lock_version == w.lock_version,
            select: 1
          )
        ),
      where:
        not exists(
          from(wo in WorkOrder,
            where: wo.snapshot_id == parent_as(:snapshot).id,
            select: 1
          )
        ),
      where:
        not exists(
          from(r in Run,
            where: r.snapshot_id == parent_as(:snapshot).id,
            select: 1
          )
        ),
      where:
        not exists(
          from(s in Step,
            where: s.snapshot_id == parent_as(:snapshot).id,
            select: 1
          )
        ),
      select: ws.id
    )
  end
end
