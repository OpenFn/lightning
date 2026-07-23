defmodule Lightning.Policies.Collections do
  @moduledoc """
  The Bodyguard Policy module for Collections.

  Access to collections is controlled by the project the collection belongs to.

  Read access (`:access_collection`) is allowed for any project member, or for a
  run that belongs to the project (via its workflow).

  Access is gated on the caller's project role, mirroring the read/write
  asymmetry used elsewhere in the app:

    * `:access_collection` (read: get, stream, download) is allowed for any
      project member, or for a run that belongs to the project.
    * `:put_collection_item` / `:delete_collection_item` (put, put_all and
      single-key delete) require at least the `:editor` role.
    * `:delete_all_collection_items` (wiping/matching-delete of a collection's
      items) requires `:owner` or `:admin`.
    * `:manage_collection` (creating, renaming or deleting the collection
      itself) requires `:owner` or `:admin`. Creation is authorized against the
      `%Project{}`, since no collection exists yet.

  The `*_collection_item(s)` actions target the key-value entries exposed by the
  Collections API; `:manage_collection` targets the collection record itself.

  Runs retain full access to collections within their own project, since jobs
  need to read and mutate collection data while executing.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Collections.Collection
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Run

  @type actions ::
          :access_collection
          | :put_collection_item
          | :delete_collection_item
          | :delete_all_collection_items
          | :manage_collection

  @editor_roles [:owner, :admin, :editor]
  @admin_roles [:owner, :admin]

  @spec authorize(
          actions(),
          User.t() | Run.t(),
          Collection.t() | Project.t()
        ) :: :ok | {:error, :unauthorized} | boolean()
  def authorize(:access_collection, %User{} = user, %Collection{} = collection) do
    Permissions.can(:project_users, :access_project, user, collection)
  end

  def authorize(action, %User{} = user, %Collection{} = collection)
      when action in [:put_collection_item, :delete_collection_item] do
    has_project_role?(user, collection.project_id, @editor_roles)
  end

  def authorize(
        :delete_all_collection_items,
        %User{} = user,
        %Collection{} = collection
      ) do
    has_project_role?(user, collection.project_id, @admin_roles)
  end

  def authorize(:manage_collection, %User{} = user, %Project{} = project) do
    has_project_role?(user, project.id, @admin_roles)
  end

  def authorize(:manage_collection, %User{} = user, %Collection{} = collection) do
    has_project_role?(user, collection.project_id, @admin_roles)
  end

  # Runs may perform any collection action within their own project.
  def authorize(_action, %Run{} = run, %Collection{} = collection) do
    Lightning.Runs.get_project_id_for_run(run) == collection.project_id
  end

  defp has_project_role?(%User{} = user, project_id, roles) do
    Projects.get_project_user_role(user, %Project{id: project_id}) in roles
  end
end
