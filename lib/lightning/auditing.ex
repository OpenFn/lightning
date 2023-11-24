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
        on: [id: a.actor_id],
        select_merge: %{actor: u},
        order_by: [desc: a.inserted_at]

    Repo.paginate(query, params)
  end
end
