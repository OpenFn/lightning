defmodule Lightning.Auditing do
  @moduledoc """
  Context for working with Audit records.
  """

  import Ecto.Query
  alias Lightning.Repo

  def list_all(params \\ %{}) do
    from(a in Lightning.Credentials.Audit, preload: [:actor])
    |> Repo.paginate(params)
  end
end
