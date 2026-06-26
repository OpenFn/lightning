defmodule Lightning.ConnectedSystemsTest do
  use Lightning.DataCase, async: true

  alias Lightning.ConnectedSystems
  alias Lightning.ConnectedSystems.ConnectedSystem

  describe "list_connected_systems/0" do
    test "returns all connected systems ordered by name" do
      insert(:connected_system, name: "zebra")
      insert(:connected_system, name: "alpha")

      assert ["alpha", "zebra"] =
               ConnectedSystems.list_connected_systems()
               |> Enum.map(& &1.name)
    end
  end

  describe "create_connected_system/1" do
    test "creates a system with a name and type" do
      user = insert(:user)

      assert {:ok, %ConnectedSystem{} = system} =
               ConnectedSystems.create_connected_system(%{
                 name: "Southwest Regional Health Tracker",
                 type: "dhis2",
                 created_by_id: user.id
               })

      assert system.name == "Southwest Regional Health Tracker"
      assert system.type == "dhis2"
      assert system.created_by_id == user.id
    end

    test "requires name and type" do
      assert {:error, changeset} =
               ConnectedSystems.create_connected_system(%{})

      assert %{name: ["can't be blank"], type: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "enforces a unique name" do
      insert(:connected_system, name: "national-id")

      assert {:error, changeset} =
               ConnectedSystems.create_connected_system(%{
                 name: "national-id",
                 type: "http"
               })

      assert %{name: ["a connected system with this name already exists"]} =
               errors_on(changeset)
    end

    test "rejects names with invalid characters" do
      assert {:error, changeset} =
               ConnectedSystems.create_connected_system(%{
                 name: "bad/name",
                 type: "http"
               })

      assert %{name: ["system name has invalid format"]} = errors_on(changeset)
    end
  end

  describe "update_connected_system/2" do
    test "updates the type" do
      system = insert(:connected_system, type: "http")

      assert {:ok, updated} =
               ConnectedSystems.update_connected_system(system, %{type: "postgresql"})

      assert updated.type == "postgresql"
    end
  end

  describe "delete_connected_system/1" do
    test "deletes the system and nullifies the reference on credentials" do
      user = insert(:user)
      system = insert(:connected_system)

      credential =
        insert(:credential, user: user, connected_system: system)

      assert {:ok, _} = ConnectedSystems.delete_connected_system(system)

      refute Lightning.Repo.get(ConnectedSystem, system.id)

      reloaded = Lightning.Repo.reload(credential)
      assert reloaded.id == credential.id
      assert is_nil(reloaded.connected_system_id)
    end
  end

  describe "get_connected_system_by_name/1" do
    test "finds by exact name" do
      system = insert(:connected_system, name: "gmail")

      assert ConnectedSystems.get_connected_system_by_name("gmail").id ==
               system.id

      assert is_nil(ConnectedSystems.get_connected_system_by_name("missing"))
    end
  end
end
