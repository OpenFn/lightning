defmodule Lightning.ServiceAccount.Audit do
  @moduledoc """
  Model for storing what service accounts do with the token endpoint.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "service_account",
    events: ["token_issued"]

  alias Lightning.ServiceAccount

  @spec token_issued(ServiceAccount.t(), [String.t()]) :: Ecto.Changeset.t()
  def token_issued(%ServiceAccount{} = account, scopes) do
    event("token_issued", account.uuid, account, %{}, %{scopes: scopes})
  end
end
