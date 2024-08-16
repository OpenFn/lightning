defmodule Lightning.Projects.File do
  @moduledoc """
  The project files module
  """
  use Lightning.Schema
  use Waffle.Ecto.Schema

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          file: Lightning.Storage.ProjectFileDefinition.Type.t(),
          created_by: Lightning.Accounts.User.t(),
          project: Lightning.Projects.Project.t(),
          type: atom()
        }

  schema "project_files" do
    field :file, Lightning.Storage.ProjectFileDefinition.Type
    field :size, :integer
    belongs_to :created_by, Lightning.Accounts.User
    belongs_to :project, Lightning.Projects.Project

    field :type, Ecto.Enum, values: [:archive]

    timestamps()
  end

  @doc """
  Creates a new file changeset.

  Unlike regular changeset functions, this expects atom keys and the project
  and user to be passed in as models.
  """
  @spec new(%{atom => any}) :: Ecto.Changeset.t()
  def new(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:size, :type])
    |> put_assoc(:created_by, attrs[:created_by])
    |> put_assoc(:project, attrs[:project])
    |> validate_required([:type, :created_by, :project])
  end

  @spec attach_file(Ecto.Changeset.t(t()), term()) :: Ecto.Changeset.t(t())
  def attach_file(project_file, uploadable \\ :invalid) do
    params = %{"file" => uploadable}

    project_file
    |> cast_attachments(params, [:file], allow_paths: true)
    |> validate_required([:id, :type, :created_by, :project, :file])
  end
end
