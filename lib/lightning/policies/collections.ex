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

  Every action except a run's needs the `collections:write` grant.

  The `*_collection_item(s)` actions target the key-value entries exposed by the
  Collections API; `:manage_collection` targets the collection record itself.

  Runs retain full access to collections within their own project, since jobs
  need to read and mutate collection data while executing.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Collections.Collection
  alias Lightning.Policies.Decision
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Run
  alias Lightning.Scope

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
          Scope.t() | Scope.actor() | Run.t(),
          Collection.t() | Project.t() | :before_target
        ) :: boolean() | {:error, :insufficient_scope | :scheduled_for_deletion}
  # Runs may perform any collection action within their own project.
  def authorize(_action, %Run{} = run, %Collection{} = collection) do
    Lightning.Runs.get_project_id_for_run(run) == collection.project_id
  end

  def authorize(action, %Scope{} = scope, subject),
    do:
      Decision.project(scope, subject, "collections:write", judge(action, scope))

  def authorize(action, actor, subject),
    do: Permissions.for_actor(actor, subject, &authorize(action, &1, subject))

  # Reads admit a support user with no membership row, as `:access_project`
  # does. The writes don't, because `Scope.holds_role?/2` ignores support
  # access.
  defp judge(:access_collection, scope), do: Scope.has_standing?(scope)

  defp judge(action, scope)
       when action in [:put_collection_item, :delete_collection_item],
       do: Scope.holds_role?(scope, @editor_roles)

  defp judge(action, scope)
       when action in [:delete_all_collection_items, :manage_collection],
       do: Scope.holds_role?(scope, @admin_roles)
end
