defmodule Lightning.Repo do
  use Ecto.Repo,
    otp_app: :lightning,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 10

  @impl true
  def init(_type, config) do
    {:ok, Keyword.put(config, :url, System.get_env("DATABASE_URL"))}
  end

  @doc """
  A small wrapper around `Repo.transaction/2'.

  Commits the transaction if the lambda returns `:ok` or `{:ok, result}`,
  rolling it back if the lambda returns `:error` or `{:error, reason}`. In both
  cases, the function returns the result of the lambda.
  """
  @spec transact((-> any()), keyword()) :: {:ok, any()} | {:error, any()}
  def transact(fun, opts \\ []) do
    transaction(
      fn ->
        case fun.() do
          {:ok, value} -> value
          :ok -> :transaction_commited
          {:error, reason} -> rollback(reason)
          :error -> rollback(:transaction_rollback_error)
        end
      end,
      opts
    )
  end
end
