defmodule Lightning.Jobs.Query do
  @moduledoc """
  Query module for finding Jobs.
  """
  alias Lightning.Jobs.{Job}
  alias Lightning.Accounts.User
  import Ecto.Query

  @doc """
  Returns all jobs accessible to a user, via their projects
  """
  @spec jobs_for(User.t()) :: Ecto.Queryable.t()
  def jobs_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])
    from(j in Job, where: j.project_id in subquery(projects))
  end

  @doc """
  Returns active jobs with their cron triggers for use in the cron scheduling
  service.
  """
  @spec enabled_cron_jobs() :: Ecto.Queryable.t()
  def enabled_cron_jobs do
    from(j in Job,
      join: t in assoc(j, :trigger),
      where: t.type == :cron,
      where: j.enabled,
      preload: [:trigger]
    )
  end
end
