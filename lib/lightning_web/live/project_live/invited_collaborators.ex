defmodule LightningWeb.ProjectLive.InvitedCollaborators do
  @moduledoc """
  This schema is used for building the changeset for adding new collaborators to a project.
  It is mirroring the `Project -> ProjectUser` relationship.
  """

  use Lightning.Schema

  embedded_schema do
    embeds_many :invited_collaborators, InvitedCollaborator, on_replace: :delete do
      field :first_name, :string
      field :last_name, :string
      field :email, :string
      field :user_id, :binary_id
      field :role, Ecto.Enum, values: [:viewer, :editor, :admin]
    end
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:invited_collaborators,
      with: &collaborators_changeset/2,
      required: true,
      drop_param: :collaborators_drop,
      sort_param: :collaborators_sort
    )
  end

  defp collaborators_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:first_name, :last_name, :email, :role])
    |> validate_required([:first_name, :last_name, :email, :role])
    |> validate_format(:email, ~r/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/)
  end
end
