defmodule Lightning.Invocation.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Projects
  alias Lightning.Invocation.Query

  import Ecto.Query

  # Project members can list jobs for a project
  def authorize(:list_runs, user, project) do
    Projects.is_member_of?(project, user)
  end

  def authorize(:read_run, user, %{id: run_id}) do
    from(r in Query.runs_for(user), where: r.id == ^run_id, select: true)
    |> Lightning.Repo.one()
    |> case do
      nil -> false
      true -> true
    end
  end

  # Default deny
  def authorize(_, _user, _project), do: false
end
