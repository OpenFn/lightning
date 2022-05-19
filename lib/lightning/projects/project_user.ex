defmodule Lightning.Projects.ProjectUser do
  @moduledoc """
  Join table to assign users to a project
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_users" do
    belongs_to :user, User
    belongs_to :project, Project
    field :delete, :boolean, virtual: true

    timestamps()
  end

  def changeset(comment, %{"delete" => "true"}) do
    %{change(comment, delete: true) | action: :delete}
  end

  @doc false
  def changeset(project_user, attrs) do
    project_user
    |> cast(attrs, [:user_id, :project_id])
    |> validate_required([:user_id])
    |> unique_constraint([:project_id, :user_id],
      message: "User already a member of this project."
    )
  end
end
