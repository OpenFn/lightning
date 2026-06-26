defmodule Lightning.ConnectedSystemsTest do
  use Lightning.DataCase, async: true

  alias Lightning.ConnectedSystems
  alias Lightning.ConnectedSystems.ConnectedSystem

  describe "create_connected_system/1" do
    test "creates a system and derives a URL-safe slug from the name" do
      assert {:ok, %ConnectedSystem{} = system} =
               ConnectedSystems.create_connected_system(%{
                 "name" => "Southwest Regional Health Tracker",
                 "type" => "dhis2"
               })

      assert system.name == "Southwest Regional Health Tracker"
      assert system.slug == "southwest-regional-health-tracker"
      assert system.type == "dhis2"
    end

    test "allows an entry with nothing but a name attached" do
      assert {:ok, system} =
               ConnectedSystems.create_connected_system(%{"name" => "Gmail"})

      assert system.type == nil
      assert system.description == nil
      assert system.slug == "gmail"
    end

    test "requires a name" do
      assert {:error, changeset} =
               ConnectedSystems.create_connected_system(%{})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a duplicate name within the instance" do
      insert(:connected_system, name: "DHIS2 National", slug: "dhis2-national")

      assert {:error, changeset} =
               ConnectedSystems.create_connected_system(%{"name" => "DHIS2 National"})

      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "rejects names that collide on slug" do
      insert(:connected_system, name: "DHIS2 National", slug: "dhis2-national")

      assert {:error, changeset} =
               ConnectedSystems.create_connected_system(%{
                 "name" => "DHIS2  national"
               })

      assert %{slug: [_ | _]} = errors_on(changeset)
    end
  end

  describe "get_connected_system_by_slug/1" do
    test "resolves an existing system by slug" do
      %{id: id} = insert(:connected_system, slug: "national-id")

      assert {:ok, %ConnectedSystem{id: ^id}} =
               ConnectedSystems.get_connected_system_by_slug("national-id")
    end

    test "returns not_found for an unknown slug" do
      assert {:error, :not_found} =
               ConnectedSystems.get_connected_system_by_slug("nope")
    end
  end

  describe "list_connected_systems/1" do
    test "lists systems ordered by name by default" do
      insert(:connected_system, name: "Zebra", slug: "zebra")
      insert(:connected_system, name: "Alpha", slug: "alpha")

      assert ["Alpha", "Zebra"] =
               ConnectedSystems.list_connected_systems()
               |> Enum.map(& &1.name)
    end
  end

  describe "update_connected_system/2" do
    test "renames and re-derives the slug" do
      system = insert(:connected_system, name: "Old", slug: "old")

      assert {:ok, updated} =
               ConnectedSystems.update_connected_system(system, %{"name" => "New Name"})

      assert updated.slug == "new-name"
    end
  end

  describe "delete_connected_system/1" do
    test "deletes a system and nilifies the link on attached credentials" do
      system = insert(:connected_system)
      user = insert(:user)

      credential =
        insert(:credential, user: user, connected_system_id: system.id)

      assert {:ok, _} = ConnectedSystems.delete_connected_system(system.id)

      assert Repo.reload(credential).connected_system_id == nil
    end

    test "returns not_found for an unknown id" do
      assert {:error, :not_found} =
               ConnectedSystems.delete_connected_system(Ecto.UUID.generate())
    end
  end
end
