defmodule LightningWeb.API.CollectionController do
  @moduledoc """
  Writes and reads a project's collection by id; the items inside a collection
  are `LightningWeb.CollectionsController`'s.

      GET /api/projects/:project_id/collections/:id
      PUT /api/projects/:project_id/collections/:id  {"name": "patients"}

  Both answer `{"data": {"id", "project_id", "name"}}`.
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Accounts.User
  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.Scope
  alias Lightning.Repo
  alias Lightning.ServiceAccount
  alias LightningWeb.API.PutRequest

  action_fallback LightningWeb.FallbackController

  # `PersonOrServiceAccountAuth` also admits a repo connection's token, which
  # `:manage_collection` has no answer for.
  plug :require_person_or_service_account

  defp require_person_or_service_account(conn, _opts) do
    case conn.assigns.current_resource do
      %User{} ->
        conn

      %ServiceAccount{} ->
        conn

      _other ->
        conn
        |> put_status(:forbidden)
        |> put_view(LightningWeb.ErrorView)
        |> render(:"403")
        |> halt()
    end
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, project} <- fetch_project(project_id),
         :ok <- authorize(conn.assigns.current_resource, project),
         {:ok, id} <- PutRequest.cast_uuid(id),
         %Collection{} = collection <- Repo.get(Collection, id),
         true <- collection.project_id == project.id do
      render_collection(conn, collection)
    else
      {:error, _reason} = error -> error
      _missing -> {:error, :not_found}
    end
  end

  @doc """
  Creates the collection under the path's id in the project, or renames the
  project's collection that has it, keeping its items.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"project_id" => project_id, "id" => id}) do
    actor = conn.assigns.current_resource

    with {:ok, project} <- fetch_project(project_id),
         :ok <- authorize(actor, project) do
      case parse_body(conn.body_params, id) do
        {:ok, attrs} ->
          put_collection(
            conn,
            Repo.get(Collection, attrs.id),
            project,
            attrs,
            actor
          )

        {:error, :invalid, errors} ->
          PutRequest.render_errors(conn, errors)
      end
    end
  end

  @body_types %{id: :binary_id, name: :string}

  defp parse_body(body, id) do
    with {:ok, changeset} <- PutRequest.changeset(body, id, {%{}, @body_types}) do
      changeset
      |> validate_required(:name)
      |> PutRequest.attrs()
    end
  end

  defp fetch_project(project_id) do
    with {:ok, project_id} <- PutRequest.cast_uuid(project_id),
         %Project{} = project <- Projects.get_project(project_id) do
      {:ok, project}
    else
      _missing -> {:error, :not_found}
    end
  end

  # A service account holds `:manage_collection` on every project, so telling
  # it the project is scheduled for deletion leaks nothing; a person gets the
  # policy's answer.
  defp authorize(actor, project) do
    case Scope.fetch(actor, project) do
      {:ok, _scope} ->
        if Permissions.can?(:collections, :manage_collection, actor, project),
          do: :ok,
          else: {:error, :forbidden}

      {:error, :project_scheduled_for_deletion}
      when is_struct(actor, ServiceAccount) ->
        {:error, :scheduled_for_deletion}

      {:error, _reason} ->
        {:error, :forbidden}
    end
  end

  defp put_collection(conn, nil, project, attrs, actor) do
    %{"project_id" => project.id, "name" => attrs.name}
    |> Collections.create_collection(actor, id: attrs.id)
    |> case do
      {:ok, collection} ->
        conn |> put_status(:created) |> render_collection(collection)

      {:error, :exceeds_limit, _message} ->
        {:error, :exceeds_limit}

      {:error, changeset} ->
        if PutRequest.unique_error?(changeset, :id) do
          # Another request created it between our lookup and our insert.
          existing = Repo.get(Collection, attrs.id)
          put_collection(conn, existing, project, attrs, actor)
        else
          render_write_error(conn, changeset)
        end
    end
  end

  defp put_collection(
         conn,
         %Collection{project_id: project_id} = collection,
         %Project{id: project_id},
         attrs,
         actor
       ) do
    case Collections.update_collection(
           collection,
           %{"name" => attrs.name},
           actor
         ) do
      {:ok, collection} -> render_collection(conn, collection)
      {:error, changeset} -> render_write_error(conn, changeset)
    end
  end

  # Lightning never moves a collection to another project.
  defp put_collection(_conn, %Collection{}, _project, _attrs, _actor),
    do: {:error, :id_taken}

  defp render_write_error(conn, changeset) do
    if PutRequest.unique_error?(changeset, :name),
      do: {:error, :name_taken},
      else: PutRequest.render_errors(conn, PutRequest.flat_errors(changeset))
  end

  defp render_collection(conn, collection) do
    json(conn, %{data: Map.take(collection, [:id, :project_id, :name])})
  end
end
