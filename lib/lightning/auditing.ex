defmodule Lightning.Auditing do
  @moduledoc """
  Context for working with Audit records.
  """

  import Ecto.Query
  alias Lightning.Accounts.User
  alias Lightning.Auditing.Audit
  alias Lightning.Repo

  def list_all(params \\ %{}) do
    from(a in Audit,
      left_join: u in User,
      on: [id: a.actor_id],
      select_merge: %{
        actor_display_identifier: u.email,
        actor_display_label:
          fragment(
            "CASE WHEN ? IS NOT NULL THEN CONCAT(?, ' ', ?) ELSE '(User deleted)' END",
            u.id,
            u.first_name,
            u.last_name
          )
      },
      order_by: [desc: a.inserted_at]
    )
    |> Repo.paginate(params)
  end
end
