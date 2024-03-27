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

  @spec capture_transaction(Ecto.Multi.t(), map) :: Ecto.Multi.t()
  def capture_transaction(multi = %Ecto.Multi{}, meta) do
    multi
    |> Carbonite.Multi.insert_transaction(%{meta: meta},
      carbonite_prefix: Lightning.Config.audit_schema()
    )
  end

  @spec capture_transaction(map, fun()) :: any
  def capture_transaction(meta, func) when is_function(func) do
    Repo.transact(fn ->
      Carbonite.insert_transaction(Lightning.Repo, %{meta: meta},
        carbonite_prefix: Lightning.Config.audit_schema()
      )
      |> case do
        {:ok, _} -> func.()
        {:error, _} -> {:error, "Failed to capture transaction."}
      end
    end)
  end
end
