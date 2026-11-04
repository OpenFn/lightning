defmodule Lightning.Repo do
  use Ecto.Repo,
    otp_app: :lightning,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 10, max_page_size: 100

  @doc """
  Like `one/2`, but answers `{:error, :not_found}` when no row matches.
  """
  @spec fetch_one(Ecto.Queryable.t(), keyword()) ::
          {:ok, term()} | {:error, :not_found}
  def fetch_one(queryable, opts \\ []) do
    case one(queryable, opts) do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end
end
