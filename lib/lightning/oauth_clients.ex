defmodule Lightning.OauthClients do
  @moduledoc """
  The OauthClients context.
  """

  import Ecto.Query, warn: false

  alias Lightning.Projects.ProjectOauthClient
  alias Ecto.Multi
  alias Lightning.Credentials.Audit
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.Project
  alias Lightning.Repo

  def change_client(%OauthClient{} = client, attrs \\ %{}) do
    OauthClient.changeset(client, attrs)
  end

  @doc """
  Returns the list of oauth clients.

  ## Examples

      iex> list_clients()
      [%OauthClient{}, ...]

  """
  def list_clients do
    Repo.all(OauthClient)
  end

  def list_clients(%Project{} = project) do
    Ecto.assoc(project, :oauth_clients)
    |> preload([:user, :project_oauth_clients, :projects])
    |> Repo.all()
  end

  @doc """
  Returns the list of oauth clients for a given user.

  ## Examples

      iex> list_clients_for_user(123)
      [%OauthClient{user_id: 123}, %OauthClient{user_id: 123},...]

  """
  def list_clients_for_user(user_id) do
    from(c in OauthClient,
      where: c.user_id == ^user_id or c.global,
      preload: :projects
    )
    |> Repo.all()
  end

  @doc """
  Gets a single oauth client.

  Raises `Ecto.NoResultsError` if the oauth client does not exist.

  ## Examples

      iex> get_client!(123)
      %OauthClient{}

      iex> get_client!(456)
      ** (Ecto.NoResultsError)

  """
  def get_client!(id), do: Repo.get!(OauthClient, id)

  def get_client_by_project_oauth_client(project_oauth_client_id) do
    query =
      from c in OauthClient,
        join: pc in assoc(c, :project_oauth_clients),
        on: pc.id == ^project_oauth_client_id

    Repo.one(query)
  end

  def get_client_for_update!(id) do
    OauthClient
    |> Repo.get!(id)
    |> Repo.preload([:project_oauth_clients, :projects])
  end

  @doc """
  Creates an OauthClient.

  ## Examples

      iex> create_client(%{field: value})
      {:ok, %OauthClient{}}

      iex> create_client(%{field: bad_value})
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
  Updates a client.

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
  Deletes a client.

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
