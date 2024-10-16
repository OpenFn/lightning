defmodule Lightning.CollectionTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Collections.Collection

  setup do
    project = insert(:project, name: "Test Project")
    {:ok, project: project}
  end

  @valid_name "valid-name"

  describe "changeset/2" do
    test "valid attributes create a valid changeset", %{project: project} do
      valid_attrs = %{
        "project_id" => project.id,
        "name" => @valid_name
      }

      changeset = Collection.changeset(%Collection{}, valid_attrs)
      assert changeset.valid?
    end

    test "missing required fields result in errors" do
      invalid_attrs = %{"project_id" => nil, "name" => nil}

      changeset = Collection.changeset(%Collection{}, invalid_attrs)
      refute changeset.valid?

      assert %{
               project_id: ["can't be blank"],
               name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "name must be URL-safe (valid format)", %{project: project} do
      valid_names = [
        "valid-name",
        "collection_123",
        "my.collection",
        "valid-collection-name"
      ]

      for name <- valid_names do
        attrs = %{"project_id" => project.id, "name" => name}
        changeset = Collection.changeset(%Collection{}, attrs)
        assert changeset.valid?, "Expected #{name} to be valid"
      end
    end

    test "name with invalid characters fails validation", %{project: project} do
      invalid_names = [
        "invalid name",
        "invalid_name!",
        "invalid/name",
        "-invalid",
        "invalid-",
        "invalid--name"
      ]

      for name <- invalid_names do
        attrs = %{"project_id" => project.id, "name" => name}
        changeset = Collection.changeset(%Collection{}, attrs)
        refute changeset.valid?, "Expected #{name} to be invalid"

        assert %{name: ["Collection name must be URL safe"]} =
                 errors_on(changeset)
      end
    end

    test "name uniqueness constraint adds error", %{project: project} do
      insert(:collection, project: project, name: "existing-name")

      attrs = %{"project_id" => project.id, "name" => "existing-name"}
      changeset = Collection.changeset(%Collection{}, attrs)

      assert {:error, changeset} = Lightning.Repo.insert(changeset)

      assert %{name: ["A collection with this name already exists"]} =
               errors_on(changeset)
    end
  end
end
