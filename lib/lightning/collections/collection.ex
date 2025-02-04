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
    field :delete, :boolean, virtual: true
    belongs_to :project, Lightning.Projects.Project
    has_many :items, Lightning.Collections.Item

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:project_id, :name])
    |> validate_required([:project_id, :name])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-z0-9]+([\-_.][a-z0-9]+)*$/,
      message: "Collection name must be URL safe"
    )
    |> unique_constraint([:name],
      message: "A collection with this name already exists"
    )
  end
end
