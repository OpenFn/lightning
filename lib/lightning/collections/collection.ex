defmodule Lightning.Collections.Collection do
  @moduledoc """
  Collection referenced by name associated to a project.
  """
  use Lightning.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          project_id: Ecto.UUID.t(),
          name: String.t(),
          byte_size_sum: integer(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "collections" do
    field :name, :string
    field :byte_size_sum, :integer
    field :raw_name, :string, virtual: true
    belongs_to :project, Lightning.Projects.Project
    has_many :items, Lightning.Collections.Item

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:project_id, :name])
    |> validate_required([:project_id, :name])
    |> validate_format(:name, ~r/^[a-z0-9]+([\-_.][a-z0-9]+)*$/,
      message: "Collection name must be URL safe"
    )
    |> unique_constraint([:name],
      message: "A collection with this name already exists"
    )
  end

  defp validate_changeset(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-z0-9]+([\-_.][a-z0-9]+)*$/,
      message: "Collection name must be URL safe"
    )
    |> unique_constraint([:name],
      message: "A collection with this name already exists"
    )
  end

  def form_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:raw_name])
    |> validate_required([:raw_name])
    |> then(fn changeset ->
      case get_change(changeset, :raw_name) do
        nil ->
          changeset

        raw_name ->
          changeset
          |> put_change(:name, Lightning.Helpers.url_safe_name(raw_name))
      end
    end)
    |> validate_changeset()
  end
end
