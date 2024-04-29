defmodule Lightning.OauthClients do
  @moduledoc """
  Manages operations for OAuth clients within the Lightning application, providing
  functions to create, retrieve, update, and delete OAuth clients, as well as managing
  their associations with projects and handling audit trails for changes.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Lightning.Credentials.Audit
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectOauthClient
  alias Lightning.Repo

  @doc """
  Prepares a changeset for creating or updating an OAuth client.

  ## Parameters

    - client: The OAuth client struct.
    - attrs: Attributes to update in the client.

  ## Returns

    - An Ecto.Changeset struct for the OAuth client.

  ## Examples

      iex> change_client(%OauthClient{}, %{name: "New Client"})
      %Ecto.Changeset{...}
  """
  def change_client(%OauthClient{} = client, attrs \\ %{}) do
    OauthClient.changeset(client, attrs)
  end

  @doc """
  Retrieves all OAuth clients associated with a given project.

  ## Parameters

    - project: The project struct to retrieve clients for.

  ## Returns

    - A list of OAuth clients associated with the project.

  ## Examples

      iex> list_clients(%Project{id: 1})
      [%OauthClient{}, %OauthClient{}]
  """
  def list_clients(%Project{} = project) do
    Ecto.assoc(project, :oauth_clients)
    |> preload([:user, :project_oauth_clients, :projects])
    |> Repo.all()
  end

  @doc """
  Retrieves all OAuth clients for a given user, including global clients.

  ## Parameters

    - user_id: The ID of the user.

  ## Returns

    - A list of OAuth clients associated with the user.

  ## Examples

      iex> list_clients_for_user(123)
      [%OauthClient{user_id: 123}, %OauthClient{user_id: 123}]
  """
  def list_clients_for_user(user_id) do
    from(c in OauthClient,
      where: c.user_id == ^user_id or c.global,
      preload: :projects
    )
    |> Repo.all()
  end

  @doc """
  Retrieves a single OAuth client by its ID, raising an error if not found.

  ## Parameters

    - id: The ID of the OAuth client to retrieve.

  ## Returns

    - The OAuth client struct.

  ## Raises

    - Ecto.NoResultsError if the OAuth client does not exist.

  ## Examples

      iex> get_client!(123)
      %OauthClient{}

      iex> get_client!(456)
      ** (Ecto.NoResultsError)
  """
  def get_client!(id), do: Repo.get!(OauthClient, id)

  @doc """
  Creates a new OAuth client with the specified attributes.

  ## Parameters

    - attrs: Attributes for the new OAuth client.

  ## Returns

    - `{:ok, oauth_client}` if the client is created successfully.
    - `{:error, changeset}` if there is an error during creation.

  ## Examples

      iex> create_client(%{name: "New Client"})
      {:ok, %OauthClient{}}

      iex> create_client(%{name: nil})
      {:error, %Ecto.Changeset{}}
  """
  def create_client(attrs \\ %{}) do
    changeset = OauthClient.changeset(%OauthClient{}, attrs)

    Multi.new()
    |> Multi.insert(:client, changeset)
    |> derive_events(changeset)
    |> Repo.transaction()
    |> case do
      {:error, _op, changeset, _changes} ->
        {:error, changeset}

      {:ok, %{client: client}} ->
        {:ok, client}
    end
  end

  @doc """
  Updates an existing OAuth client with the specified attributes.

  ## Parameters
  - client: The existing OauthClient to update.
  - attrs: A map of attributes to update.

  ## Returns
  - A tuple {:ok, oauth_client} if update is successful.
  - A tuple {:error, changeset} if update fails.

  ## Examples
      iex> update_client(client, %{field: new_value})
      {:ok, %OauthClient{}}

      iex> update_client(client, %{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  def update_client(%OauthClient{} = client, attrs) do
    changeset = OauthClient.changeset(client, attrs)

    Multi.new()
    |> Multi.update(:client, changeset)
    |> derive_events(changeset)
    |> Repo.transaction()
    |> case do
      {:error, :client, changeset, _changes} ->
        {:error, changeset}

      {:ok, %{client: client}} ->
        {:ok, client}
    end
  end

  defp derive_events(
         multi,
         %Ecto.Changeset{data: %OauthClient{__meta__: %{state: state}}} =
           changeset
       ) do
    case changeset.changes do
      map when map_size(map) == 0 ->
        multi

      _ ->
        project_oauth_clients_multi =
          Ecto.Changeset.get_change(changeset, :project_oauth_clients, [])
          |> Enum.reduce(Multi.new(), fn changeset, multi ->
            derive_event(multi, changeset)
          end)

        multi
        |> Multi.insert(
          :audit,
          fn %{client: client} ->
            Audit.event(
              if(state == :built, do: "created", else: "updated"),
              client.id,
              client.user_id,
              changeset
            )
          end
        )
        |> Multi.append(project_oauth_clients_multi)
    end
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :delete,
           data: %Lightning.Projects.ProjectOauthClient{}
         } = changeset
       ) do
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{client: client} ->
        Audit.event(
          "removed_from_project",
          client.id,
          client.user_id,
          %{
            before: %{
              project_id: Ecto.Changeset.get_field(changeset, :project_id)
            },
            after: %{project_id: nil}
          }
        )
      end
    )
  end

  defp derive_event(
         multi,
         %Ecto.Changeset{
           action: :insert,
           data: %Lightning.Projects.ProjectOauthClient{}
         } = changeset
       ) do
    Multi.insert(
      multi,
      {:audit, Ecto.Changeset.get_field(changeset, :project_id)},
      fn %{client: client} ->
        Audit.event("added_to_project", client.id, client.user_id, %{
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
         data: %Lightning.Projects.ProjectOauthClient{}
       }) do
    multi
  end

  @doc """
  Deletes an OAuth client and all associated data.

  ## Parameters
  - client: The OauthClient to delete.

  ## Returns
  - A tuple {:ok, oauth_client} if deletion is successful.
  - A tuple {:error, changeset} if deletion fails.

  ## Examples
      iex> delete_client(client)
      {:ok, %OauthClient{}}

      iex> delete_client(client)
      {:error, %Ecto.Changeset{}}
  """
  def delete_client(%OauthClient{} = client) do
    Multi.new()
    |> Multi.run(:remove_projects, fn _repo, _changes ->
      case remove_project_oauth_clients(client.id) do
        {:error, reason} -> {:error, reason}
        {count, _} -> {:ok, count}
      end
    end)
    |> Multi.delete(:client, client)
    |> Multi.insert(:audit, fn _ ->
      Audit.event("deleted", client.id, client.user_id)
    end)
    |> Repo.transaction()
  end

  defp remove_project_oauth_clients(client_id) do
    from(poc in ProjectOauthClient, where: [oauth_client_id: ^client_id])
    |> Repo.delete_all()
  end
end
