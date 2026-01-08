defmodule LightningWeb.ProjectLive.InvitedCollaborators do
  @moduledoc """
  This schema is used for building the changeset for adding new collaborators to a project.
  It is mirroring the `Project -> ProjectUser` relationship.
  """

  use Lightning.Schema

  embedded_schema do
    embeds_many :invited_collaborators, InvitedCollaborator,
      on_replace: :delete do
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
    |> validate_format(:email, ~r/^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$/)
  end

  def validate_collaborators(schema, params) do
    changeset = changeset(schema, params)

    changeset =
      if changeset.valid? do
        validate_collaborator_emails(changeset)
      else
        changeset
      end

    apply_changeset_action(changeset)
  end

  defp validate_collaborator_emails(changeset) do
    collaborators = Ecto.Changeset.get_embed(changeset, :invited_collaborators)
    existing_emails = fetch_existing_emails(collaborators)

    updated_collaborators =
      Enum.map(collaborators, fn collaborator ->
        validate_collaborator_email(collaborator, existing_emails)
      end)

    Ecto.Changeset.put_embed(
      changeset,
      :invited_collaborators,
      updated_collaborators
    )
  end

  defp fetch_existing_emails(collaborators) do
    collaborators
    |> Enum.map(&Ecto.Changeset.get_field(&1, :email))
    |> Lightning.Accounts.list_users_by_emails()
    |> Enum.map(fn user -> String.downcase(user.email) end)
  end

  defp validate_collaborator_email(collaborator, existing_emails) do
    Ecto.Changeset.validate_change(collaborator, :email, fn :email, email ->
      if String.downcase(email) in existing_emails do
        [email: "This email is already taken"]
      else
        []
      end
    end)
  end

  defp apply_changeset_action(changeset) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, %{invited_collaborators: collaborators}} -> {:ok, collaborators}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
