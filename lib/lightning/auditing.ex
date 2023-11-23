defmodule Lightning.Auditing do
  @moduledoc """
  Context for working with Audit records.
  """

  import Ecto.Query
  alias Lightning.Repo
  alias Lightning.Auditing.Model, as: Audit
  alias Lightning.Accounts.User

  def list_all(params \\ %{}) do
    query =
      from a in Audit,
        left_join: u in User,
        on: u.id == a.actor_id,
        select: %{
          id: a.id,
          event: a.event,
          item_type: a.item_type,
          item_id: a.item_id,
          changes: a.changes,
          actor_id: a.actor_id,
          inserted_at: a.inserted_at,
          actor: u
        },
        order_by: [desc: a.inserted_at]

    Repo.paginate(query, params)
  end
end
