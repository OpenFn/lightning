defmodule Lightning.Credentials.KeychainCredential do
  @moduledoc """
  Keychain credentials allow jobs to automatically select different credentials
  based on data from the run's input dataclip using JSONPath expressions.
  """

  use Lightning.Schema
  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          path: String.t() | nil,
          created_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          default_credential:
            Credential.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "keychain_credentials" do
    field :name, :string
    field :path, :string

    belongs_to :created_by, User
    belongs_to :default_credential, Credential
    belongs_to :project, Project

    timestamps()
  end

  @doc false
  def changeset(keychain_credential, attrs) do
    keychain_credential
    |> cast(attrs, [
      :name,
      :path,
      :default_credential_id
    ])
    |> validate_required([:name, :path])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:path, min: 1, max: 500)
    |> validate_jsonpath(:path)
    |> unique_constraint([:name, :project_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> foreign_key_constraint(:default_credential_id)
    |> validate_default_credential_belongs_to_project()
  end

  defp validate_jsonpath(changeset, field) do
    validate_change(changeset, field, fn ^field, path ->
      case validate_jsonpath_syntax(path) do
        :ok -> []
        {:error, message} -> [{field, message}]
      end
    end)
  end

  defp validate_jsonpath_syntax(path) do
    # Basic JSONPath validation - starts with $ and contains valid characters
    cond do
      not String.starts_with?(path, "$") ->
        {:error, "JSONPath must start with '$'"}

      not Regex.match?(~r/^[$@]([.\[\]'"\w\-\*\?:,\s\(\)@=]+)*$/, path) ->
        {:error, "Invalid JSONPath syntax"}

      true ->
        :ok
    end
  end

  defp validate_default_credential_belongs_to_project(changeset) do
    project = get_field(changeset, :project)
    default_credential_id = get_field(changeset, :default_credential_id)

    project_id = if project, do: project.id, else: nil

    if project_id && default_credential_id do
      case Lightning.Repo.get_by(
             Lightning.Projects.ProjectCredential,
             project_id: project_id,
             credential_id: default_credential_id
           ) do
        nil ->
          add_error(
            changeset,
            :default_credential_id,
            "must belong to the same project"
          )

        _ ->
          changeset
      end
    else
      changeset
    end
  end
end
