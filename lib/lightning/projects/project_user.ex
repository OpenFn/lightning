defmodule Lightning.Projects.ProjectUser do
  @moduledoc """
  Join table to assign users to a project
  """
  use Lightning.Schema

  import EctoEnum

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project

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

  schema "project_users" do
    belongs_to :user, User
    belongs_to :project, Project
    field :delete, :boolean, virtual: true
    field :failure_alert, :boolean, default: false
    field :role, RolesEnum
    field :digest, DigestEnum, default: :never

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
    |> unique_constraint([:project_id],
      name: "project_owner_unique_index",
      message: "project can have only one owner"
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
