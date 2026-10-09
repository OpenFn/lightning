defmodule Lightning.Policies.CollectionsTest do
  @moduledoc """
  Collections access is gated on the caller's project role.

  Read (`:access_collection`) routes through `:project_users, :access_project`,
  which loads the project and therefore sees `scheduled_deletion`. The write
  actions do not: `Policies.Collections.has_project_role?/3` builds a
  `%Project{id: project_id}` and asks `Projects.get_project_user_role/2` about
  it, so whether the project is still operable is never consulted.

  The result is that writes are *more* permissive than reads on a project that
  has been shut down.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Policies.Collections
  alias Lightning.Policies.Permissions

  setup do
    editor = insert(:user)
    admin = insert(:user)

    project_users = [
      %{user_id: editor.id, role: :editor},
      %{user_id: admin.id, role: :admin}
    ]

    project = insert(:project, project_users: project_users)

    # Scheduling deletion removes no membership rows, so both users still hold
    # a real project_users row on this project.
    scheduled_project =
      insert(:project,
        project_users: project_users,
        scheduled_deletion: DateTime.utc_now() |> DateTime.add(7, :day)
      )

    %{
      editor: editor,
      admin: admin,
      collection: insert(:collection, project: project),
      scheduled_project: scheduled_project,
      scheduled_collection: insert(:collection, project: scheduled_project)
    }
  end

  # PUT /collections/:name/:key and PUT /collections/:name (put_all) both
  # authorise `:put_collection_item`; DELETE /collections/:name/:key
  # authorises `:delete_collection_item`; DELETE /collections/:name
  # (delete_all) authorises `:delete_all_collection_items`.
  @write_actions [
    :put_collection_item,
    :delete_collection_item,
    :delete_all_collection_items,
    :manage_collection
  ]

  describe "a project scheduled for deletion" do
    test "refuses collection writes for an :editor", %{
      editor: editor,
      collection: collection,
      scheduled_collection: scheduled_collection
    } do
      # Control: the same actor CAN write on a live project, so every refusal
      # below is about the project's lifecycle and not about the role.
      assert_can(:put_collection_item, editor, collection)

      # Control: read access is ALREADY refused, because `:access_collection`
      # delegates to `:access_project`, which loads the project. The writes
      # below are therefore more permissive than the read.
      refute_can(:access_collection, editor, scheduled_collection)

      assert allowed_writes(editor, scheduled_collection) == []
    end

    test "refuses collection writes for an :admin", %{
      admin: admin,
      collection: collection,
      scheduled_collection: scheduled_collection
    } do
      assert_can(:delete_all_collection_items, admin, collection)

      refute_can(:access_collection, admin, scheduled_collection)

      assert allowed_writes(admin, scheduled_collection) == []
    end

    test "refuses collection creation for an :admin", %{
      admin: admin,
      scheduled_project: scheduled_project
    } do
      # `:manage_collection` is also authorised against the %Project{} itself,
      # since a collection being created does not exist yet.
      refute_can(:manage_collection, admin, scheduled_project)
    end
  end

  describe ":manage_collection on a project" do
    test "is held by its owner and admins, not its editors or viewers" do
      [owner, admin, editor, viewer, outsider] = insert_list(5, :user)

      project =
        insert(:project,
          project_users: [
            %{user_id: owner.id, role: :owner},
            %{user_id: admin.id, role: :admin},
            %{user_id: editor.id, role: :editor},
            %{user_id: viewer.id, role: :viewer}
          ]
        )

      assert_can(:manage_collection, owner, project)
      assert_can(:manage_collection, admin, project)
      refute_can(:manage_collection, editor, project)
      refute_can(:manage_collection, viewer, project)
      refute_can(:manage_collection, outsider, project)
    end

    test "is held by a service account on any project" do
      {account, _key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      assert Permissions.can?(
               Collections,
               :manage_collection,
               account,
               insert(:project)
             )
    end
  end

  defp allowed_writes(user, collection) do
    for action <- @write_actions,
        Permissions.can?(Collections, action, user, collection),
        do: action
  end

  defp assert_can(action, user, subject) do
    assert Permissions.can?(Collections, action, user, subject),
           "expected #{action} to be ALLOWED for #{describe_subject(user, subject)}"
  end

  defp refute_can(action, user, subject) do
    refute Permissions.can?(Collections, action, user, subject),
           "expected #{action} to be REFUSED for #{describe_subject(user, subject)}"
  end

  defp describe_subject(user, subject) do
    "user #{user.id} on #{inspect(subject.__struct__)} #{subject.id}"
  end
end
