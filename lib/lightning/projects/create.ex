defmodule Lightning.Projects.Handlers do
  @moduledoc false

  alias Lightning.Strategy
  alias Lightning.Projects.Project
  alias Lightning.Projects.Events

  # """
  # Projects.create()

  # make a project

  # <- create a subscription with the project

  # -> Events.project_created
  # -> schedule_project_addition_emails

  # -> call cache_run_limits

  # """

  @spec create(multi :: Ecto.Multi.t() | nil, map()) :: Strategy.t()
  def create(multi \\ nil, attrs) do
    Strategy.new(multi || Ecto.Multi.new())
    |> Strategy.insert(
      :project,
      %Project{} |> Project.project_with_users_changeset(attrs)
    )
    |> Strategy.afterwards(fn %{project: project} ->
      Events.project_created(project)
      # schedule_project_addition_emails(%Project{project_users: []}, project)
    end)
  end
end
