defmodule Lightning.Auditing do
  @moduledoc """
  Context for working with Audit records.
  """

  import Ecto.Query
  alias Lightning.Repo

  def list_all(params \\ %{}) do
    from(a in Lightning.Credentials.Audit.base_query(),
      left_join: u in Lightning.Accounts.User,
      on: [id: a.actor_id],
      select_merge: %{actor: u},
      order_by: [desc: a.inserted_at]
    )
    |> Repo.paginate(params)
  end
end
