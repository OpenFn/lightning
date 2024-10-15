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
    |> unique_constraint([:name])
  end
end
