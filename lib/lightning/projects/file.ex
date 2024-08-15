defmodule Lightning.Projects.File do
  use Lightning.Schema

  schema "project_files" do
    field :path, :string
    field :size, :integer
    belongs_to :created_by, Lightning.Accounts.User
    belongs_to :project, Lightning.Projects.Project

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
    |> cast(attrs, [:path, :size])
    |> put_assoc(:created_by, attrs[:created_by])
    |> put_assoc(:project, attrs[:project])
    |> validate_required([:path, :size, :created_by, :project])
  end
end
