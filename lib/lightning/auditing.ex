defmodule Lightning.Auditing do
  @moduledoc """
  Context for working with Audit records.
  """

  import Ecto.Query
  alias Lightning.Repo

  def list_all(params \\ %{}) do
    from(a in Lightning.Credentials.Audit,
      order_by: [desc: a.inserted_at]
    )
    |> Repo.paginate(params)
    |> try_to_get_actors()
  end

  defp try_to_get_actors(page) do
    page
    |> Map.put(
      :entries,
      Enum.map(page.entries, fn entry ->
        entry
        |> Map.put(:actor, Repo.get(Lightning.Accounts.User, entry.actor_id))
      end)
    )
  end
end
