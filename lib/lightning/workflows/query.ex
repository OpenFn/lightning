defmodule Lightning.Workflows.Query do
  @moduledoc """
  Query module for finding Jobs.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job

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
end
