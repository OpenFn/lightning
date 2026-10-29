defmodule Lightning.CollectionsTest do
  use Lightning.DataCase, async: true

  import Lightning.QueryCountHelpers

  alias Lightning.Collections
  alias Lightning.Collections.Collection

  describe "get_collection_by_id/1" do
    test "returns the collection with the id, or nil" do
      %{id: id} = insert(:collection)

      assert %Collection{id: ^id} = Collections.get_collection_by_id(id)
      assert Collections.get_collection_by_id(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_collection_for_project/2" do
    test "finds a collection only in its own project" do
      %{id: id, project_id: project_id} = insert(:collection)

      assert {:ok, %Collection{id: ^id}} =
               Collections.get_collection_for_project(project_id, id)

      for {project_id, id} <- [
            {insert(:project).id, id},
            {project_id, Ecto.UUID.generate()},
            {project_id, "not-a-uuid"}
          ] do
        assert Collections.get_collection_for_project(project_id, id) ==
                 {:error, :not_found}
      end
    end
  end

  describe "get_collection/2" do
    test "returns the collection for the given project" do
      name = "shared-name"
      %{id: project_id_1} = project_1 = insert(:project)
      %{id: project_id_2} = project_2 = insert(:project)
      %{id: id_1} = insert(:collection, name: name, project: project_1)
      %{id: id_2} = insert(:collection, name: name, project: project_2)

      assert {:ok, %Collection{id: ^id_1}} =
               Collections.get_collection(project_id_1, name)

      assert {:ok, %Collection{id: ^id_2}} =
               Collections.get_collection(project_id_2, name)
    end

    test "returns not_found when the collection does not exist in the project" do
      %{id: project_id} = insert(:project)

      assert {:error, :not_found} =
               Collections.get_collection(project_id, "nonexistent")
    end
  end

  describe "resolve_collection/3" do
    setup do
      user = insert(:user)
      mine = insert(:project, project_users: [%{user: user, role: :viewer}])
      theirs = insert(:project)

      %{
        user: user,
        mine: insert(:collection, name: "shared", project: mine),
        theirs: insert(:collection, name: "shared", project: theirs)
      }
    end

    test "finds the one collection of that name the user has standing on",
         %{user: user, mine: %{id: id}} do
      assert {:ok, %Collection{id: ^id}} =
               Collections.resolve_collection(user, "shared")
    end

    test "is ambiguous only among collections the user has standing on",
         %{user: user, theirs: theirs} do
      insert(:project_user, user: user, project_id: theirs.project_id)

      assert {:error, :ambiguous_name} =
               Collections.resolve_collection(user, "shared")
    end

    test "narrows to the project named by project_id",
         %{user: user, theirs: %{id: id} = theirs} do
      insert(:project_user, user: user, project_id: theirs.project_id)

      assert {:ok, %Collection{id: ^id}} =
               Collections.resolve_collection(user, "shared", theirs.project_id)
    end

    test "finds nothing in a project the user has no standing on",
         %{user: user, theirs: theirs} do
      assert {:error, :not_found} =
               Collections.resolve_collection(user, "shared", theirs.project_id)

      assert {:error, :not_found} =
               Collections.resolve_collection(insert(:user), "shared")
    end

    test "finds nothing for a name no collection has, or a project_id that isn't a UUID",
         %{user: user} do
      assert {:error, :not_found} =
               Collections.resolve_collection(user, "nonexistent")

      assert {:error, :not_found} =
               Collections.resolve_collection(user, "shared", "not-a-uuid")
    end

    test "reads a 16-character project_id as text, not as a raw UUID",
         %{user: user} do
      raw = "abcdefghijklmnop"
      {:ok, project_id} = Ecto.UUID.load(raw)

      project =
        insert(:project,
          id: project_id,
          project_users: [%{user: user, role: :viewer}]
        )

      insert(:collection, name: "shared", project: project)

      assert {:error, :not_found} =
               Collections.resolve_collection(user, "shared", raw)
    end

    test "counts support access as standing, and only where it is allowed",
         %{theirs: theirs} do
      support_user = insert(:user, support_user: true)

      assert {:error, :not_found} =
               Collections.resolve_collection(support_user, "shared")

      Repo.update_all(
        from(p in Lightning.Projects.Project,
          where: p.id == ^theirs.project_id
        ),
        set: [allow_support_access: true]
      )

      theirs_id = theirs.id

      assert {:ok, %Collection{id: ^theirs_id}} =
               Collections.resolve_collection(support_user, "shared")
    end

    test "resolves for a member who hasn't met the project's MFA requirement" do
      user = insert(:user, mfa_enabled: false)

      project =
        insert(:project, requires_mfa: true, project_users: [%{user: user}])

      %{id: id} = insert(:collection, name: "guarded", project: project)

      assert {:ok, %Collection{id: ^id}} =
               Collections.resolve_collection(user, "guarded")
    end

    test "gives a run standing on its own project only",
         %{mine: %{id: id} = mine, theirs: theirs} do
      workflow = insert(:simple_workflow, project: mine.project)
      work_order = insert(:workorder, workflow: workflow)

      run =
        insert(:run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_trigger: hd(workflow.triggers)
        )

      assert {:ok, %Collection{id: ^id}} =
               Collections.resolve_collection(run, "shared")

      assert {:error, :not_found} =
               Collections.resolve_collection(run, "shared", theirs.project_id)
    end

    test "reads standing in two queries however many projects share the name",
         %{user: user, mine: %{id: id}} do
      insert(:collection, name: "shared")

      assert {{:ok, %Collection{id: ^id}}, 2} =
               count_queries(fn ->
                 Collections.resolve_collection(user, "shared")
               end)
    end
  end

  describe "create_collection/3" do
    setup do
      %{actor: insert(:user)}
    end

    test "creates a collection and records its creator", %{actor: actor} do
      %{id: project_id} = insert(:project)
      name = "col1_project1"

      assert {:ok, %Collection{id: id, project_id: ^project_id, name: ^name}} =
               Collections.create_collection(
                 %{"project_id" => project_id, "name" => name},
                 actor
               )

      assert [audit] = collection_audits(id)
      assert audit.event == "created"
      assert audit.actor_id == actor.id
      assert audit.actor_type == :user
      assert audit.changes.before == nil

      assert audit.changes.after == %{
               "name" => name,
               "project_id" => project_id
             }
    end

    test "records a service account as the creator" do
      {account, _key} =
        Lightning.ServiceAccountHelpers.service_account_with_key()

      %{id: project_id} = insert(:project)

      assert {:ok, %Collection{id: id}} =
               Collections.create_collection(
                 %{"project_id" => project_id, "name" => "patients"},
                 account
               )

      assert [audit] = collection_audits(id)
      assert audit.actor_id == account.uuid
      assert audit.actor_type == :service_account
      assert audit.metadata["service_account_id"] == account.id
    end

    test "creates under the id it is given, never one cast from attrs", %{
      actor: actor
    } do
      %{id: project_id} = insert(:project)
      id = Ecto.UUID.generate()

      assert {:ok, %Collection{id: ^id}} =
               Collections.create_collection(
                 %{"project_id" => project_id, "name" => "given"},
                 actor,
                 id: id
               )

      assert {:ok, %Collection{id: other_id}} =
               Collections.create_collection(
                 %{"project_id" => project_id, "name" => "cast", "id" => id},
                 actor
               )

      refute other_id == id
    end

    test "refuses an id already in use as a changeset error", %{actor: actor} do
      existing = insert(:collection)

      assert {:error, changeset} =
               Collections.create_collection(
                 %{"project_id" => insert(:project).id, "name" => "other"},
                 actor,
                 id: existing.id
               )

      assert {_message, opts} = changeset.errors[:id]
      assert opts[:constraint] == :unique
      assert collection_audits(existing.id) == []
    end

    test "returns an error when collection name is taken", %{actor: actor} do
      %{id: project_id1} = insert(:project)
      name = "col1_project1"

      assert {:ok, %Collection{project_id: ^project_id1, name: ^name}} =
               Collections.create_collection(
                 %{"project_id" => project_id1, "name" => name},
                 actor
               )

      assert {:error,
              %{
                errors: [
                  name:
                    {"A collection with this name already exists",
                     [
                       constraint: :unique,
                       constraint_name: "collections_project_id_name_index"
                     ]}
                ]
              }} =
               Collections.create_collection(
                 %{"project_id" => project_id1, "name" => name},
                 actor
               )
    end

    test "writes nothing when the limit is exceeded", %{actor: actor} do
      %{id: project_id1} = insert(:project)
      %{id: project_id2} = insert(:project)

      assert {:ok, %Collection{project_id: ^project_id1, name: "col1"}} =
               Collections.create_collection(
                 %{"project_id" => project_id1, "name" => "col1"},
                 actor
               )

      message = %Lightning.Extensions.Message{text: "some error"}

      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_create,
        fn %{"project_id" => _project_id} ->
          {:error, :exceeds_limit, message}
        end
      )

      id = Ecto.UUID.generate()

      assert {:error, :exceeds_limit, ^message} =
               Collections.create_collection(
                 %{"project_id" => project_id2, "name" => "col2"},
                 actor,
                 id: id
               )

      refute Repo.get(Collection, id)
      assert collection_audits(id) == []
    end

    test "returns an error if invalid attributes are provided", %{actor: actor} do
      attrs = %{"name" => nil, "project_id" => Ecto.UUID.generate()}

      assert {:error, changeset} = Collections.create_collection(attrs, actor)

      assert %{name: ["can't be blank"]} == errors_on(changeset)
    end
  end

  describe "update_collection/3" do
    setup do
      %{actor: insert(:user)}
    end

    test "renames a collection, keeping its items, and records who did", %{
      actor: actor
    } do
      collection = insert(:collection, name: "old-name")
      insert(:collection_item, collection: collection, key: "k", value: "v")

      assert {:ok, %Collection{name: "updated-name"}} =
               Collections.update_collection(
                 collection,
                 %{"name" => "updated-name"},
                 actor
               )

      assert Collections.get(collection, "k").value == "v"

      assert [audit] = collection_audits(collection.id)
      assert audit.event == "updated"
      assert audit.actor_id == actor.id
      assert audit.changes.before == %{"name" => "old-name"}
      assert audit.changes.after == %{"name" => "updated-name"}
    end

    test "a collection another request deleted is a concurrent edit, not a raise",
         %{actor: actor} do
      collection = insert(:collection, name: "old-name")
      Repo.delete!(collection)

      assert Collections.update_collection(
               collection,
               %{"name" => "updated-name"},
               actor
             ) == {:error, :concurrent_edit}
    end

    test "records nothing when the name is unchanged", %{actor: actor} do
      collection = insert(:collection, name: "same-name")

      assert {:ok, %Collection{name: "same-name"}} =
               Collections.update_collection(
                 collection,
                 %{"name" => "same-name"},
                 actor
               )

      assert collection_audits(collection.id) == []
    end

    test "never moves a collection to another project", %{actor: actor} do
      collection = insert(:collection)
      other_project = insert(:project)

      assert {:ok, _collection} =
               Collections.update_collection(
                 collection,
                 %{"name" => "moved", "project_id" => other_project.id},
                 actor
               )

      assert Repo.reload!(collection).project_id == collection.project_id
    end

    test "returns an error if invalid attributes are provided", %{actor: actor} do
      collection = insert(:collection)

      assert {:error, changeset} =
               Collections.update_collection(collection, %{name: nil}, actor)

      assert %{name: ["can't be blank"]} == errors_on(changeset)
      assert collection_audits(collection.id) == []
    end
  end

  describe "delete_collection/1" do
    test "deletes a collection" do
      %{id: collection_id} = insert(:collection)

      assert {:ok, %Collection{id: ^collection_id}} =
               Collections.delete_collection(collection_id)
    end

    test "returns an error when collection does not exist" do
      assert {:error, :not_found} =
               Collections.delete_collection(Ecto.UUID.generate())
    end
  end

  describe "list_collections/1" do
    test "returns a list of collections with default ordering and preloading" do
      collection1 = insert(:collection, name: "B Collection")
      collection2 = insert(:collection, name: "A Collection")

      result = Collections.list_collections()

      assert Enum.map(result, & &1.id) == [collection2.id, collection1.id]
    end

    test "returns collections ordered by specified field" do
      collection1 = insert(:collection, inserted_at: ~N[2024-01-01 00:00:00])
      collection2 = insert(:collection, inserted_at: ~N[2024-02-01 00:00:00])

      result = Collections.list_collections(order_by: [asc: :inserted_at])

      assert Enum.map(result, & &1.id) == [collection1.id, collection2.id]
    end

    test "preloads specified associations" do
      project = insert(:project)
      insert(:collection, project: project)

      result = Collections.list_collections(preload: [:project])

      assert Enum.map(result, & &1.project.id) == [project.id]
    end
  end

  defp collection_audits(collection_id) do
    Repo.all(
      from a in Lightning.Collections.Audit.base_query(),
        where: a.item_id == ^collection_id
    )
  end
end
