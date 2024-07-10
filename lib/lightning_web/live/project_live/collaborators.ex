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
    |> validate_format(:email, ~r/^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$/)
  end

  @spec prepare_for_insertion(%__MODULE__{}, map(), [map(), ...]) ::
          {:ok, [map(), ...]} | {:error, Ecto.Changeset.t()}
  def prepare_for_insertion(schema, attrs, current_project_users) do
    changeset = changeset(schema, attrs)

    {changeset, non_existing_users} =
      if changeset.valid? do
        collaborators = get_embed(changeset, :collaborators)

        emails = Enum.map(collaborators, &get_field(&1, :email))

        found_users = Lightning.Accounts.list_users_by_emails(emails)

        # Create a list of users or emails based on whether the user is found
        user_or_email_list =
          Enum.map(emails, fn email ->
            case Enum.find(found_users, fn user -> user.email == email end) do
              nil -> {:not_found, email}
              user -> {:found, user}
            end
          end)

        # Use Enum.split_with to separate found users from non-existing emails
        {found, not_found} =
          Enum.split_with(user_or_email_list, fn
            {:found, _user} -> true
            {:not_found, _email} -> false
          end)

        # Extract users and emails from the tuples
        found_users = Enum.map(found, fn {:found, user} -> user end)

        non_existing_users =
          Enum.map(not_found, fn {:not_found, email} -> email end)

        updated_collaborators =
          validate_collaborators(
            collaborators,
            found_users,
            current_project_users
          )

        {put_embed(changeset, :collaborators, updated_collaborators),
         non_existing_users}
      else
        {changeset, []}
      end

    with {:ok, %{collaborators: collaborators}} <-
           apply_action(changeset, :insert) do
      collaborators =
        Enum.map(collaborators, fn c ->
          Map.take(c, [:user_id, :role])
        end)

      {:ok, %{collaborators: collaborators, to_invite: non_existing_users}}
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
          u.email == get_field(collaborator, :email)
        end)

      collaborator
      |> put_change(:user_id, existing_user && existing_user.id)
      |> validate_change(:email, fn :email, _email ->
        cond do
          Enum.find(current_project_users, &(&1.user_id == existing_user.id)) ->
            [email: "This account is already part of this project"]

          true ->
            []
        end
      end)
    end)
  end
end
