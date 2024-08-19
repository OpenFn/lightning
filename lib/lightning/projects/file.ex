defmodule Lightning.Projects.File do
  @moduledoc """
  The project files module
  """
  use Lightning.Schema

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          file: String.t(),
          created_by: Lightning.Accounts.User.t(),
          project: Lightning.Projects.Project.t(),
          type: atom(),
          status: atom()
        }

  schema "project_files" do
    field :file, :string
    field :size, :integer

    field :status, Ecto.Enum,
      values: [:enqueued, :in_progress, :completed, :failed]

    belongs_to :created_by, Lightning.Accounts.User
    belongs_to :project, Lightning.Projects.Project

    field :type, Ecto.Enum, values: [:export]

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
    |> cast(attrs, [:size, :type, :status, :file])
    |> put_assoc(:created_by, attrs[:created_by])
    |> put_assoc(:project, attrs[:project])
    |> validate_required([:type, :created_by, :project])
  end
end
