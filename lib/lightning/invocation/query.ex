defmodule Lightning.Invocation.Query do
  @moduledoc """
  Query functions for working with Events, Runs and Dataclips
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Run

  @doc """
  Runs for a specific user
  """
  @spec runs_for(User.t()) :: Ecto.Queryable.t()
  def runs_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(r in Run,
      join: e in assoc(r, :event),
      join: p in subquery(projects),
      on: e.project_id == p.id
    )
  end
end
