defmodule Lightning.Credentials do
  @moduledoc """
  The Credentials context.
  """

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]
  alias Lightning.Credentials
  alias Lightning.AuthProviders.Google
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
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Returns the list of credentials for a given user.

  ## Examples

      iex> list_credentials_for_user(123)
      [%Credential{user_id: 123}, %Credential{user_id: 123},...]

  """
  def list_credentials_for_user(user_id) do
    from(c in Credential, where: c.user_id == ^user_id, preload: :projects)
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
    case changeset.changes do
      map when map_size(map) == 0 ->
        multi

      _ ->
        project_credentials_multi =
          Ecto.Changeset.get_change(changeset, :project_credentials, [])
          |> Enum.reduce(Multi.new(), fn changeset, multi ->
            derive_event(multi, changeset)
          end)

        multi
        |> Multi.insert(
          :audit,
          fn %{credential: credential} ->
            Audit.event("updated", credential.id, credential.user_id, changeset)
          end
        )
        |> Multi.append(project_credentials_multi)
    end
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :delete,
           data: %Lightning.Projects.ProjectCredential{}
         } = changeset
       ) do
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{credential: credential} ->
        "removed_from_project"
        |> Audit.event(credential.id, credential.user_id, %{
          before: %{
            project_id: Ecto.Changeset.get_field(changeset, :project_id)
          },
          after: %{project_id: nil}
        })
      end
    )
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :insert,
           data: %Lightning.Projects.ProjectCredential{}
         } = changeset
       ) do
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{credential: credential} ->
        "added_to_project"
        |> Audit.event(credential.id, credential.user_id, %{
          before: %{project_id: nil},
          after: %{
            project_id: Ecto.Changeset.get_field(changeset, :project_id)
          }
        })
      end
    )
  end

  defp derive_event(multi, %Ecto.Changeset{
         action: :update,
         data: %Lightning.Projects.ProjectCredential{}
       }) do
    multi
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
    Multi.new()
    |> Multi.delete(:credential, credential)
    |> Multi.insert(:audit, fn _ ->
      Audit.event("deleted", credential.id, credential.user_id)
    end)
    |> Repo.transaction()
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

  @doc """
  Given a credential and a user, returns a list of invalid projects—i.e., those
  that the credential is shared with but that the user does not have access to.

  This is used to generate a validation error when a credential cannot be
  transferred.

  ## Examples

      iex> can_credential_be_shared_to_user(credential_id, user_id)
      []

      iex> can_credential_be_shared_to_user(credential_id, user_id)
      ["52ea8758-6ce5-43d7-912f-6a1e1f11dc55"]
  """
  def invalid_projects_for_user(credential_id, user_id) do
    project_credentials =
      from(pc in Lightning.Projects.ProjectCredential,
        where: pc.credential_id == ^credential_id,
        select: pc.project_id
      )
      |> Repo.all()

    project_users =
      from(pu in Lightning.Projects.ProjectUser,
        where: pu.user_id == ^user_id,
        select: pu.project_id
      )
      |> Repo.all()

    project_credentials -- project_users
  end

  # TODO: this doesn't need to be Google specific. It should work for any standard OAuth2 credential.
  @spec maybe_refresh_token(nil | Lightning.Credentials.Credential.t()) ::
          {:error, :invalid_config}
          | {:ok, Lightning.Credentials.Credential.t()}
  def maybe_refresh_token(%Credential{schema: "googlesheets"} = credential) do
    token_body = Google.TokenBody.new(credential.body)

    if still_fresh(token_body) do
      {:ok, credential}
    else
      with {:ok, %OAuth2.Client{} = client} <- Google.build_client(),
           {:ok, %OAuth2.AccessToken{} = token} <-
             Google.refresh_token(client, token_body),
           token <- Google.TokenBody.from_oauth2_token(token) do
        Credentials.update_credential(credential, %{
          body: token |> Lightning.Helpers.json_safe()
        })
      end
    end
  end

  def maybe_refresh_token(%Credential{} = credential), do: {:ok, credential}
  def maybe_refresh_token(nil), do: {:ok, nil}

  defp still_fresh(
         %{expires_at: expires_at},
         threshold \\ 5,
         time_unit \\ :minute
       ) do
    current_time = DateTime.utc_now()
    expiration_time = DateTime.from_unix!(expires_at)

    time_remaining = DateTime.diff(expiration_time, current_time, time_unit)

    time_remaining >= threshold
  end
end
