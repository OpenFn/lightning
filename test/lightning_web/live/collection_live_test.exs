defmodule LightningWeb.CollectionLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Collections

  # The page is drawn by React from data-props. Its sorting, empty state,
  # dialogs, the URL-safe name it shows and how it shows the reply's field
  # errors are tested in the design system's AdminCollectionsPage.test.tsx;
  # the events it sends in assets/test/design-system/AdminCollectionsPage.test.tsx.
  @page "#admin-collections-page"

  defp props(view), do: page_props(view, @page)
  defp names(view), do: Enum.map(props(view)["collections"], & &1["name"])

  defp row(view, collection),
    do: Enum.find(props(view)["collections"], &(&1["id"] == collection.id))

  defp create_collection(view, values),
    do: push_page_event(view, @page, "create_collection", values)

  defp update(view, collection, values),
    do:
      push_page_event(
        view,
        @page,
        "update_collection",
        Map.put(values, "id", collection.id)
      )

  defp delete_collection(view, id),
    do: push_page_event(view, @page, "delete_collection", %{"collection" => id})

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "Regular user cannot access the collections page", %{conn: conn} do
      {:ok, conn} =
        live(conn, ~p"/settings/collections")
        |> follow_redirect(conn, ~p"/projects")

      assert conn.resp_body =~ "No Access"
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser

    test "Superuser can access the collections page", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings/collections")

      assert html =~ "Collections"
      assert %{"collections" => [], "projectOptions" => _} = props(view)
    end

    test "Collections are listed for superuser, with their project and size", %{
      conn: conn
    } do
      collection_1 =
        insert(:collection,
          name: "Collection A",
          project: build(:project, name: "Project A"),
          byte_size_sum: 100
        )

      collection_2 =
        insert(:collection,
          name: "Collection B",
          project: build(:project, name: "Project B")
        )

      {:ok, view, _html} =
        live(conn, ~p"/settings/collections", on_error: :raise)

      assert %{
               "name" => "Collection A",
               "projectName" => "Project A",
               "byteSizeSum" => 100,
               "projectId" => project_id
             } = row(view, collection_1)

      assert project_id == collection_1.project_id
      assert row(view, collection_2)
    end

    test "Collections arrive sorted by name; the page sorts the other columns",
         %{conn: conn} do
      insert(:collection, name: "B Collection")
      insert(:collection, name: "A Collection")

      {:ok, view, _html} =
        live(conn, ~p"/settings/collections", on_error: :raise)

      assert names(view) == ["A Collection", "B Collection"]
    end

    test "every project is offered for the form, by name", %{conn: conn} do
      insert(:project, name: "Zed")
      insert(:project, name: "Alpha")

      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      assert [["Alpha", _], ["Zed", _]] =
               props(view)["projectOptions"]
               |> Enum.filter(fn [name, _] -> name in ["Alpha", "Zed"] end)
    end

    test "Superuser can delete a collection", %{conn: conn} do
      collection = insert(:collection, name: "Delete Me")

      {:ok, view, _html} =
        live(conn, ~p"/settings/collections", on_error: :raise)

      assert row(view, collection)

      assert delete_collection(view, collection.id) =~ "Collection deleted"

      refute row(view, collection)
      refute Lightning.Repo.get(Collections.Collection, collection.id)
    end

    test "a delete with an unknown or malformed id is refused", %{conn: conn} do
      collection = insert(:collection, name: "Keep Me")

      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      delete_collection(view, Ecto.UUID.generate())
      assert_reply(view, %{error: "Collection not found"})
      delete_collection(view, "not-a-uuid")
      assert_reply(view, %{error: "Collection not found"})
      assert row(view, collection)
    end

    test "Superuser can create a collection", %{conn: conn} do
      project = insert(:project, name: "Target")

      {:ok, view, _html} =
        live(conn, ~p"/settings/collections", on_error: :raise)

      # The server derives the URL-safe name from what was typed.
      assert create_collection(view, %{
               "rawName" => "New Collection",
               "projectId" => project.id
             }) =~ "Collection created successfully"

      assert [%{"name" => "new-collection", "projectName" => "Target"}] =
               props(view)["collections"]
    end

    test "a create for a project that does not exist is refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      create_collection(view, %{
        "rawName" => "Orphan",
        "projectId" => Ecto.UUID.generate()
      })

      assert_reply(view, %{fieldErrors: %{"projectId" => ["Choose a project"]}})
      assert Collections.list_collections() == []
    end

    test "Superuser can update a collection, renaming it and moving it", %{
      conn: conn
    } do
      project = insert(:project, name: "Old")
      other = insert(:project, name: "New Home")
      collection = insert(:collection, name: "old-collection", project: project)

      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      assert update(view, collection, %{
               "rawName" => "Updated Collection",
               "projectId" => other.id
             }) =~ "Collection updated successfully"

      assert %{"name" => "updated-collection", "projectName" => "New Home"} =
               row(view, collection)
    end

    test "Creating a collection with a name that already exists fails", %{
      conn: conn
    } do
      project = insert(:project)
      collection = insert(:collection, name: "duplicate-name", project: project)

      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      create_collection(view, %{
        "rawName" => collection.name,
        "projectId" => project.id
      })

      assert_reply(view, %{
        error: "Please fix the errors below.",
        fieldErrors: %{
          "rawName" => ["A collection with this name already exists"]
        }
      })

      assert length(Collections.list_collections()) == 1
    end
  end
end
