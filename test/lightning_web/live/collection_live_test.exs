defmodule LightningWeb.CollectionLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "Regular user cannot access the collections page", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/settings/collections")
        |> follow_redirect(conn, ~p"/projects")

      assert html =~ "No Access"
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser

    test "Superuser can access the collections page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/collections")

      assert html =~ "Collections"
      assert html =~ "No collection found. Create a new one."
    end

    test "Collections are listed for superuser", %{conn: conn} do
      collection_1 =
        insert(:collection,
          name: "Collection A",
          project: build(:project, name: "Project A")
        )

      collection_2 =
        insert(:collection,
          name: "Collection B",
          project: build(:project, name: "Project B")
        )

      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      assert has_element?(view, "tr#collections-table-row-#{collection_1.id}")
      assert has_element?(view, "tr#collections-table-row-#{collection_2.id}")
    end

    test "Collections can be sorted by name for superuser", %{conn: conn} do
      insert(:collection, name: "B Collection")
      insert(:collection, name: "A Collection")

      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      sorted_names = get_sorted_collection_names(view)
      assert sorted_names == ["A Collection", "B Collection"]

      view |> element("span[phx-click='sort']") |> render_click()
      sorted_names = get_sorted_collection_names(view)
      assert sorted_names == ["B Collection", "A Collection"]
    end

    test "Superuser can delete a collection", %{conn: conn} do
      collection = insert(:collection, name: "Delete Me")

      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      assert has_element?(view, "tr#collections-table-row-#{collection.id}")

      {:ok, view, html} =
        view
        |> element("#delete-collection-#{collection.id}-modal_confirm_button")
        |> render_click()
        |> follow_redirect(conn, ~p"/settings/collections")

      assert html =~ "Collection deleted successfully"

      refute has_element?(view, "tr#collections-table-row-#{collection.id}")
    end

    test "Superuser can create a collection via the modal", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user: user}])
      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      assert has_element?(view, "#collection-form-new")

      view
      |> form("#collection-form-new", collection: %{raw_name: "New Collection"})
      |> render_change()

      assert has_element?(view, "input[type='text'][value='new-collection']")

      {:ok, _view, html} =
        view
        |> form("#collection-form-new",
          collection: %{raw_name: "New Collection", project_id: project.id}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/settings/collections")

      assert html =~ "Collection created successfully"
      assert html =~ "new-collection"
      assert html =~ project.name
    end

    test "Canceling collection creation modal closes the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/collections")

      assert has_element?(view, "#collection-form-new")

      view
      |> form("#collection-form-new", collection: %{raw_name: "New Collection"})
      |> render_change()

      {:ok, _view, html} =
        view
        |> element("#cancel-collection-creation-new")
        |> render_click()
        |> follow_redirect(conn, ~p"/settings/collections")

      refute html =~ "new-collection"
    end
  end

  defp get_sorted_collection_names(view) do
    html = render(view)

    html
    |> Floki.parse_document!()
    |> Floki.find("#collections-table tr")
    |> Enum.map(fn tr ->
      Floki.find(tr, "td:nth-child(1)")
      |> Floki.text()
      |> String.trim()
    end)
    |> Enum.filter(fn name -> String.length(name) > 0 end)
  end
end
