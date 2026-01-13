defmodule Lightning.Credentials.CredentialBody do
  @moduledoc """
  Per-environment credential body storage.

  Each credential can have multiple environment variants (e.g., "main", "staging", "prod")
  with different configuration values.
  """
  use Lightning.Schema

  alias Lightning.Credentials.Credential

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t(),
          body: map() | nil,
          credential_id: Ecto.UUID.t(),
          credential: Credential.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "credential_bodies" do
    field :name, :string, default: "main"
    field :body, Lightning.Encrypted.Map, redact: true

    belongs_to :credential, Credential

    timestamps()
  end

  def changeset(credential_body, attrs) do
    credential_body
    |> cast(attrs, [:name, :body, :credential_id])
    |> validate_required([:name, :body, :credential_id])
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9_-]{0,31}$/,
      message: "must be a short slug"
    )
    |> validate_credential_body_complexity()
    |> unique_constraint([:credential_id, :name])
    |> assoc_constraint(:credential)
  end

  defp validate_credential_body_complexity(changeset) do
    validate_change(changeset, :body, fn :body, body ->
      max_values = Lightning.Config.max_credential_sensitive_values()
      sensitive_count = count_sensitive_values(body)

      if sensitive_count > max_values do
        [
          body:
            "contains too many sensitive keys (#{sensitive_count}). Max allowed is #{max_values}"
        ]
      else
        []
      end
    end)
  end

  defp count_sensitive_values(body) when is_map(body) do
    body
    |> Lightning.Credentials.sensitive_values_from_body()
    |> length()
  end

  defp count_sensitive_values(_), do: 0
end
