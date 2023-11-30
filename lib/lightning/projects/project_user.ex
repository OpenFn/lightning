defmodule Lightning.Projects.ProjectUser do
  @moduledoc """
  Join table to assign users to a project
  """
  use Ecto.Schema
  import Ecto.Changeset
  import EctoEnum

  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil
        }

  defenum(RolesEnum, :role, [
    :viewer,
    :editor,
    :admin,
    :owner
  ])

  defenum(DigestEnum, :digest, [
    :never,
    :daily,
    :weekly,
    :monthly
  ])

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_users" do
    belongs_to :user, User
    belongs_to :project, Project
    field :delete, :boolean, virtual: true
    field :failure_alert, :boolean, default: true
    field :role, RolesEnum, default: :editor
    field :digest, DigestEnum, default: :weekly

    timestamps()
  end

  @doc false
  def changeset(project_user, attrs) do
    project_user
    |> cast(attrs, [
      :delete,
      :user_id,
      :project_id,
      :role,
      :digest,
      :failure_alert
    ])
    |> validate_required([:user_id])
    |> unique_constraint([:project_id, :user_id],
      message: "user already a member of this project."
    )
    |> maybe_remove_user()
  end

  defp maybe_remove_user(changeset) do
    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
