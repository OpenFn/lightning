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
      select_merge: %{actor: u},
      order_by: [desc: a.inserted_at]
    )
    |> Repo.paginate(params)
  end

  @schema Application.compile_env!(:lightning, :transaction_audit_schema)

  @spec capture_transaction(Ecto.Multi.t(), map) :: Ecto.Multi.t()
  def capture_transaction(multi, meta) do
    multi
    |> Carbonite.Multi.insert_transaction(%{meta: meta},
      carbonite_prefix: @schema
    )
  end
end
