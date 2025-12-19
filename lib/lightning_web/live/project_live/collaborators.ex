defmodule LightningWeb.ProjectLive.Collaborators do
  @moduledoc """
  This schema is used for building the changeset for adding new collaborators to a project.
  It is mirroring the `Project -> ProjectUser` relationship.
  """

  use Lightning.Schema

  embedded_schema do
    embeds_many :collaborators, Collaborator, on_replace: :delete do
      field :email, :string
      field :user_id, :binary_id
      field :role, Ecto.Enum, values: [:viewer, :editor, :admin]
    end
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:collaborators,
      with: &collaborators_changeset/2,
      required: true,
      drop_param: :collaborators_drop,
      sort_param: :collaborators_sort
    )
  end

  defp collaborators_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:email, :role])
    |> validate_required([:email, :role])
    |> validate_format(:email, ~r/^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$/)
  end

  @spec prepare_for_insertion(%__MODULE__{}, map(), [map(), ...]) ::
          {:ok, [map(), ...]} | {:error, Ecto.Changeset.t()}
  def prepare_for_insertion(schema, attrs, current_project_users) do
    changeset = changeset(schema, attrs)

    changeset =
      if changeset.valid? do
        collaborators = get_embed(changeset, :collaborators)

        emails = Enum.map(collaborators, &get_field(&1, :email))

        existing_users =
          Lightning.Accounts.list_users_by_emails(emails)

        existing_emails =
          Enum.map(existing_users, fn user -> String.downcase(user.email) end)

        {existing_collaborators, new_collaborators} =
          Enum.split_with(collaborators, fn collaborator ->
            Enum.member?(
              existing_emails,
              get_field(collaborator, :email) |> String.downcase()
            )
          end)

        updated_collaborators =
          validate_collaborators(
            existing_collaborators,
            existing_users,
            current_project_users
          )

        put_embed(
          changeset,
          :collaborators,
          updated_collaborators ++ new_collaborators
        )
      else
        changeset
      end

    with {:ok, %{collaborators: collaborators}} <-
           apply_action(changeset, :insert) do
      {:ok, collaborators}
    end
  end

  defp validate_collaborators(
         collaborators,
         existing_users,
         current_project_users
       ) do
    Enum.map(collaborators, fn collaborator ->
      existing_user =
        Enum.find(existing_users, fn u ->
          u.email == String.downcase(get_field(collaborator, :email))
        end)

      collaborator
      |> put_change(:user_id, existing_user && existing_user.id)
      |> validate_change(:email, fn :email, _email ->
        cond do
          is_nil(existing_user) ->
            []

          Enum.find(current_project_users, &(&1.user_id == existing_user.id)) ->
            [email: "This account is already part of this project"]

          true ->
            []
        end
      end)
    end)
  end
end
