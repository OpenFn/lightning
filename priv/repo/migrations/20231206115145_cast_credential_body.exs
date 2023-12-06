defmodule Lightning.Repo.Migrations.CastCredentialBody do
  use Ecto.Migration

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  def change do
    [{Lightning.Vault, Application.get_env(:lightning, Lightning.Vault, [])}]
    |> Supervisor.start_link(strategy: :one_for_one)

    Credential
    |> Repo.all()
    |> Enum.each(fn %{body: body} = orig_credential ->
      case Credentials.cast_body(orig_credential) do
        %{body: ^body} ->
          :ok

        _changed ->
          Credentials.update_credential(orig_credential, %{body: body})
      end
    end)
  end
end
