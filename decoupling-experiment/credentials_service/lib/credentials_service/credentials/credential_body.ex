defmodule CredentialsService.Credentials.CredentialBody do
  @moduledoc """
  Per-environment credential body. `body` is encrypted at rest via Cloak
  (`CredentialsService.Encrypted.Map`) and is `redact: true` so it never leaks
  into logs or inspect output. This is the only place secret values are stored
  (OAuth tokens included: there is no separate tokens table).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CredentialsService.Credentials.Credential

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credential_bodies" do
    field :name, :string, default: "main"
    field :body, CredentialsService.Encrypted.Map, redact: true

    belongs_to :credential, Credential

    timestamps()
  end

  @doc false
  def changeset(credential_body, attrs) do
    credential_body
    |> cast(attrs, [:name, :body, :credential_id])
    |> validate_required([:name, :body])
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9_-]{0,31}$/,
      message: "must be a short slug"
    )
    |> validate_body_complexity()
    |> unique_constraint([:credential_id, :name])
  end

  # Mirrors Lightning's sensitive-values cap (default 50).
  @max_sensitive_values 50

  defp validate_body_complexity(changeset) do
    validate_change(changeset, :body, fn :body, body ->
      count = body |> sensitive_values() |> length()

      if count > @max_sensitive_values do
        [
          body:
            "contains too many sensitive keys (#{count}). Max allowed is #{@max_sensitive_values}"
        ]
      else
        []
      end
    end)
  end

  @doc "Collects string leaf values from a (possibly nested) body map."
  def sensitive_values(body) when is_map(body) do
    body
    |> Map.values()
    |> Enum.flat_map(&collect/1)
  end

  def sensitive_values(_), do: []

  defp collect(v) when is_binary(v) and v != "", do: [v]
  defp collect(v) when is_map(v), do: sensitive_values(v)
  defp collect(v) when is_list(v), do: Enum.flat_map(v, &collect/1)
  defp collect(_), do: []
end
