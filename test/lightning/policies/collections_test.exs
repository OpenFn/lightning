defmodule Lightning.Policies.CollectionsTest do
  @moduledoc """
  Collections access is decided by the caller's project role, and every action
  is refused on a project scheduled for deletion, reads and writes alike.
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

      account = %{account | grants: MapSet.new(["collections:write"])}

      assert Permissions.can?(
               Collections,
               :manage_collection,
               account,
               insert(:project)
             )
    end
  end

  describe "an operator holding collections:write" do
    setup do
      {account, _key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      project = insert(:project)

      %{
        account: %{account | grants: MapSet.new(["collections:write"])},
        project: project,
        collection: insert(:collection, project: project)
      }
    end

    test "may manage a project or a collection, and put items", %{
      account: account,
      project: project,
      collection: collection
    } do
      assert Collections.authorize(:manage_collection, account, project) == true

      assert Collections.authorize(:manage_collection, account, collection) ==
               true

      assert Collections.authorize(:put_collection_item, account, collection) ==
               true
    end

    test "may read items, needing no grant but its own", %{
      account: account,
      collection: collection
    } do
      assert Collections.authorize(:access_collection, account, collection) ==
               true
    end

    test "without the grant, is refused as insufficient_scope", %{
      account: account,
      project: project
    } do
      account = %{account | grants: MapSet.new(["projects:write"])}
      {:ok, scope} = Lightning.Scope.fetch(account, project)

      assert Collections.authorize(:manage_collection, scope, project) ==
               {:error, {:insufficient_scope, "collections:write"}}
    end
  end

  describe "asked with a scope, on a project scheduled for deletion" do
    setup %{scheduled_project: scheduled_project} do
      owner = insert(:user)

      insert(:project_user,
        project: scheduled_project,
        user: owner,
        role: :owner
      )

      %{owner: owner}
    end

    test "an owner is told, a raw owner or non-member is not", %{
      owner: owner,
      scheduled_project: scheduled_project
    } do
      {:ok, scope} = Lightning.Scope.fetch(owner, scheduled_project)

      assert Collections.authorize(:manage_collection, scope, scheduled_project) ==
               {:error, :scheduled_for_deletion}

      assert Collections.authorize(:manage_collection, owner, scheduled_project) ==
               false

      scheduled_collection = insert(:collection, project: scheduled_project)

      assert Collections.authorize(
               :access_collection,
               scope,
               scheduled_collection
             ) == {:error, :scheduled_for_deletion}

      {:ok, outsider_scope} =
        Lightning.Scope.fetch(insert(:user), scheduled_project)

      assert Collections.authorize(
               :manage_collection,
               outsider_scope,
               scheduled_project
             ) == {:error, :no_standing}
    end
  end

  test "a scope for one project is refused another project's subject" do
    owner = insert(:user)

    project =
      insert(:project, project_users: [%{user_id: owner.id, role: :owner}])

    other = insert(:project)
    {:ok, scope} = Lightning.Scope.fetch(owner, project)

    assert Collections.authorize(:manage_collection, scope, other) == false
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
