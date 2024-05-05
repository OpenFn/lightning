defmodule Lightning.OauthClients do
  @moduledoc """
  Manages operations for OAuth clients within the Lightning application, providing
  functions to create, retrieve, update, and delete OAuth clients, as well as managing
  their associations with projects and handling audit trails for changes.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthClientAudit
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
    changeset =
      OauthClient.changeset(%OauthClient{}, attrs) |> maybe_associate_projects()

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

  defp maybe_associate_projects(changeset) do
    if Ecto.Changeset.get_field(changeset, :global, false) do
      projects = Repo.all(Project)

      project_oauth_clients =
        Enum.map(projects, fn %Project{id: project_id} ->
          %ProjectOauthClient{project_id: project_id}
        end)

      Ecto.Changeset.put_assoc(
        changeset,
        :project_oauth_clients,
        project_oauth_clients
      )
    else
      changeset
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
    |> manage_projects_association(client, changeset)
    |> Repo.transaction()
    |> case do
      {:error, :client, changeset, _changes} ->
        {:error, changeset}

      {:ok, %{client: client}} ->
        {:ok, client |> Repo.reload() |> Repo.preload(:project_oauth_clients)}
    end
  end

  defp manage_projects_association(
         multi,
         %OauthClient{global: true} = old_client,
         %Ecto.Changeset{changes: %{global: false}} = changeset
       ) do
    if Ecto.Changeset.changed?(changeset, :project_oauth_clients) do
      provided_projects =
        Ecto.Changeset.get_assoc(changeset, :project_oauth_clients, :struct)

      associated_projects_query =
        from(poc in ProjectOauthClient,
          where: poc.oauth_client_id == ^old_client.id
        )

      multi
      |> Multi.run(:projects_to_add, fn _, _ -> {:ok, provided_projects} end)
      |> Multi.run(:associated_projects, fn _repo, _ ->
        projects = Repo.all(associated_projects_query)
        {:ok, projects}
      end)
      |> Multi.run(:audit_removed_associations, fn _repo,
                                                   %{
                                                     associated_projects:
                                                       projects
                                                   } ->
        projects
        |> Enum.reduce(Multi.new(), fn project, acc ->
          Multi.insert(acc, {:audit, project.id}, fn _ ->
            OauthClientAudit.event(
              "removed_from_project",
              old_client.id,
              old_client.user_id,
              %{
                before: %{project_id: project.project_id},
                after: %{project_id: nil}
              }
            )
          end)
        end)
        |> Repo.transaction()
      end)
      |> Multi.run(:audit_added_associations, fn _,
                                                 %{projects_to_add: projects} ->
        projects
        |> Enum.reduce(Multi.new(), fn project, acc ->
          Multi.insert(acc, {:audit, project.project_id}, fn _ ->
            OauthClientAudit.event(
              "added_to_project",
              old_client.id,
              old_client.user_id,
              %{
                before: %{project_id: nil},
                after: %{project_id: project.project_id}
              }
            )
          end)
        end)
        |> Multi.insert(:audit_client_update, fn _ ->
          OauthClientAudit.event(
            "updated",
            old_client.id,
            old_client.user_id,
            changeset
          )
        end)
        |> Repo.transaction()
      end)
    else
      associated_projects_query =
        from(poc in ProjectOauthClient,
          where: poc.oauth_client_id == ^old_client.id
        )

      multi
      |> Multi.run(:associated_projects, fn _repo, _ ->
        projects = Repo.all(associated_projects_query)
        {:ok, projects}
      end)
      |> Multi.delete_all(
        :remove_associated_projects,
        associated_projects_query
      )
      |> Multi.run(:audit_removed_associations, fn _repo,
                                                   %{
                                                     associated_projects:
                                                       projects
                                                   } ->
        projects
        |> Enum.reduce(Multi.new(), fn project, acc ->
          Multi.insert(acc, {:audit, project.id}, fn _ ->
            OauthClientAudit.event(
              "removed_from_project",
              old_client.id,
              old_client.user_id,
              %{
                before: %{project_id: project.project_id},
                after: %{project_id: nil}
              }
            )
          end)
        end)
        |> Multi.insert(:audit_client_update, fn _ ->
          OauthClientAudit.event(
            "updated",
            old_client.id,
            old_client.user_id,
            changeset
          )
        end)
        |> Repo.transaction()
      end)
    end
  end

  defp manage_projects_association(
         multi,
         %OauthClient{global: false} = old_client,
         %Ecto.Changeset{changes: %{global: true}} = changeset
       ) do
    projects = Repo.all(Project)

    project_oauth_clients =
      Enum.map(projects, fn %Project{id: project_id} ->
        %ProjectOauthClient{project_id: project_id}
      end)

    changeset =
      Ecto.Changeset.put_assoc(
        changeset,
        :project_oauth_clients,
        project_oauth_clients
      )

    multi
    |> Multi.update(:updated_client, changeset)
    |> Multi.run(:audit_events, fn _repo, _ ->
      project_oauth_clients
      |> Enum.reduce(Multi.new(), fn project, acc ->
        Multi.insert(acc, {:audit, project.project_id}, fn _ ->
          OauthClientAudit.event(
            "added_to_project",
            old_client.id,
            old_client.user_id,
            %{
              before: %{project_id: nil},
              after: %{project_id: project.project_id}
            }
          )
        end)
      end)
      |> Multi.insert(:audit_client_update, fn _ ->
        OauthClientAudit.event(
          "updated",
          old_client.id,
          old_client.user_id,
          changeset
        )
      end)
      |> Repo.transaction()
    end)
  end

  defp manage_projects_association(
         multi,
         _,
         _
       ) do
    multi
  end

  defp derive_events(
         multi,
         %Ecto.Changeset{data: %OauthClient{__meta__: %{state: state}}} =
           changeset
       ) do
    case changeset.changes |> IO.inspect() do
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
            OauthClientAudit.event(
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
        OauthClientAudit.event(
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
        OauthClientAudit.event("added_to_project", client.id, client.user_id, %{
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
      OauthClientAudit.event("deleted", client.id, client.user_id)
    end)
    |> Repo.transaction()
  end

  defp remove_project_oauth_clients(client_id) do
    from(poc in ProjectOauthClient, where: [oauth_client_id: ^client_id])
    |> Repo.delete_all()
  end
end
