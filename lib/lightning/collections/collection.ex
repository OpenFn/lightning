defmodule Lightning.Collections.Collection do
  @moduledoc """
  Collection referenced by name associated to a project.
  """
  use Lightning.Schema

  import Ecto.Changeset

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
