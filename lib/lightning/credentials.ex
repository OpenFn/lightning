defmodule Lightning.Credentials do
  @moduledoc """
  The Credentials context.
  """

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]
  alias Lightning.Repo
  alias Ecto.Multi

  alias Lightning.Credentials.{Audit, Credential, SensitiveValues}
  alias Lightning.Projects.Project

  @doc """
  Returns the list of credentials.

  ## Examples

      iex> list_credentials()
      [%Credential{}, ...]

  """
  def list_credentials do
    Repo.all(Credential)
  end

  def list_credentials(%Project{} = project) do
    Ecto.assoc(project, :credentials)
    |> Repo.all()
  end

  @doc """
  Returns the list of credentials for a given user.

  ## Examples

      iex> list_credentials_for_user(123)
      [%Credential{user_id: 123}, %Credential{user_id: 123},...]

  """
  def list_credentials_for_user(user_id) do
    from(c in Credential, where: c.user_id == ^user_id)
    |> Repo.all()
  end

  @doc """
  Gets a single credential.

  Raises `Ecto.NoResultsError` if the Credential does not exist.

  ## Examples

      iex> get_credential!(123)
      %Credential{}

      iex> get_credential!(456)
      ** (Ecto.NoResultsError)

  """
  def get_credential!(id), do: Repo.get!(Credential, id)

  @doc """
  Creates a credential.

  ## Examples

      iex> create_credential(%{field: value})
      {:ok, %Credential{}}

      iex> create_credential(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_credential(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(
      :credential,
      Credential.changeset(%Credential{}, attrs |> coerce_json_field("body"))
    )
    |> Multi.insert(:audit, fn %{credential: credential} ->
      Audit.event("created", credential.id, credential.user_id)
    end)
    |> Repo.transaction()
    |> case do
      {:error, :credential, changeset, _changes} ->
        {:error, changeset}

      {:ok, %{credential: credential}} ->
        {:ok, credential}
    end
  end

  @doc """
  Updates a credential.

  ## Examples

      iex> update_credential(credential, %{field: new_value})
      {:ok, %Credential{}}

      iex> update_credential(credential, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_credential(%Credential{} = credential, attrs) do
    changeset = change_credential(credential, attrs)

    Multi.new()
    |> Multi.update(:credential, changeset)
    |> derive_events(changeset)
    |> Repo.transaction()
    |> case do
      {:error, :credential, changeset, _changes} ->
        {:error, changeset}

      {:ok, %{credential: credential}} ->
        {:ok, credential}
    end
  end

  defp derive_events(
         multi,
         %Ecto.Changeset{data: %Credential{}} = changeset
       ) do
    multi
    |> Multi.insert(
      :audit,
      fn %{credential: credential} ->
        Audit.event("updated", credential.id, credential.user_id, changeset)
      end
    )
    |> Multi.append(
      Ecto.Changeset.get_change(changeset, :project_credentials, [])
      |> Enum.reduce(Multi.new(), fn changeset, multi ->
        multi
        |> Multi.append(derive_events(multi, changeset))
      end)
    )
  end

  defp derive_events(
         multi,
         %Ecto.Changeset{
           data: %Lightning.Projects.ProjectCredential{}
         } = changeset
       ) do
    multi
    |> Multi.insert(
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{credential: credential} ->
        case changeset.action do
          :insert ->
            "added_to_project"
            |> Audit.event(credential.id, credential.user_id, %{
              before: %{project_id: nil},
              after: %{
                project_id: Ecto.Changeset.get_field(changeset, :project_id)
              }
            })

          :delete ->
            "removed_from_project"
            |> Audit.event(credential.id, credential.user_id, %{
              before: %{
                project_id: Ecto.Changeset.get_field(changeset, :project_id)
              },
              after: %{project_id: nil}
            })
        end
      end
    )
  end

  @doc """
  Deletes a credential.

  ## Examples

      iex> delete_credential(credential)
      {:ok, %Credential{}}

      iex> delete_credential(credential)
      {:error, %Ecto.Changeset{}}

  """
  def delete_credential(%Credential{} = credential) do
    Repo.delete(credential)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking credential changes.

  ## Examples

      iex> change_credential(credential)
      %Ecto.Changeset{data: %Credential{}}

  """
  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(
      credential,
      attrs |> coerce_json_field("body")
    )
  end

  @spec sensitive_values_for(Ecto.UUID.t() | Credential.t() | nil) :: [any()]
  def sensitive_values_for(id) when is_binary(id) do
    sensitive_values_for(get_credential!(id))
  end

  def sensitive_values_for(nil), do: []

  def sensitive_values_for(%Credential{body: body}) do
    if is_nil(body) do
      []
    else
      SensitiveValues.secret_values(body)
    end
  end
end
