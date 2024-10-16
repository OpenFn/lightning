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
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "collections" do
    field :name, :string
    belongs_to :project, Lightning.Projects.Project

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
end
