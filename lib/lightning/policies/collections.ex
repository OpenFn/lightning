defmodule Lightning.Policies.Collections do
  @moduledoc """
  The Bodyguard Policy module for Collections.

  Access to collections is controlled by the project the collection belongs to.

  Access is gated on the caller's project role, mirroring the read/write
  asymmetry used elsewhere in the app:

    * `:access_collection` (read: get, stream, download) is allowed for any
      project member.
    * `:put_collection_item` / `:delete_collection_item` (put, put_all and
      single-key delete) require at least the `:editor` role.
    * `:delete_all_collection_items` (wiping/matching-delete of a collection's
      items) requires `:owner` or `:admin`.
    * `:manage_collection` (creating, renaming or deleting the collection
      itself) requires `:owner` or `:admin`. Creation is authorized against the
      `%Project{}`, since no collection exists yet.

  Every action needs the `collections:write` grant.

  The `*_collection_item(s)` actions target the key-value entries exposed by the
  Collections API; `:manage_collection` targets the collection record itself.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Collections.Collection
  alias Lightning.Policies.Decision
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
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
          Scope.t() | Scope.actor(),
          Collection.t() | Project.t() | :before_target
        ) :: Decision.answer()
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
