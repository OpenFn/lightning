defmodule LightningWeb.ProjectLive.CollaboratorProject do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

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
  end

  @spec prepare_for_insertion(%__MODULE__{}, map(), [map(), ...]) ::
          {:ok, [map(), ...]} | {:error, Ecto.Changeset.t()}
  def prepare_for_insertion(schema, attrs, current_project_users) do
    changeset = changeset(schema, attrs)

    changeset =
      if changeset.valid? do
        collaborators = get_embed(changeset, :collaborators)

        emails = Enum.map(collaborators, &get_field(&1, :email))

        existing_users = Lightning.Accounts.list_users_by_emails(emails)

        updated_collaborators =
          validate_collaborators(
            collaborators,
            existing_users,
            current_project_users
          )

        put_embed(changeset, :collaborators, updated_collaborators)
      else
        changeset
      end

    with {:ok, %{collaborators: collaborators}} <-
           apply_action(changeset, :insert) do
      collaborators =
        Enum.map(collaborators, fn c ->
          Map.take(c, [:user_id, :role])
        end)

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
          u.email == get_field(collaborator, :email)
        end)

      collaborator
      |> put_change(:user_id, existing_user && existing_user.id)
      |> validate_change(:email, fn :email, _email ->
        cond do
          is_nil(existing_user) ->
            [email: "There is no account connected this email"]

          Enum.find(current_project_users, &(&1.user_id == existing_user.id)) ->
            [email: "This account is already part of this project"]

          true ->
            []
        end
      end)
    end)
  end
end
