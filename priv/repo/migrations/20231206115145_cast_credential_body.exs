defmodule Lightning.Repo.Migrations.CastCredentialBody do
  use Ecto.Migration

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  def change do
    [{Lightning.Vault, Application.get_env(:lightning, Lightning.Vault, [])}]
    |> Enum.reject(fn {mod, _} -> Process.whereis(mod) end)
    |> Supervisor.start_link(strategy: :one_for_one)

    Repo.transaction(fn ->
      Credential
      |> Repo.all()
      |> Enum.each(&Credentials.migrate_credential_body/1)
    end)
  end
end
