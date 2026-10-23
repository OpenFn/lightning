defmodule LightningWeb.API.Projects.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "listing" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "page links carry the page size applied and no other query parameter",
         %{conn: conn, project: project} do
      page =
        conn
        |> get(~p"/api/projects?page=1&page_size=500&foo=bar")
        |> json_response(200)

      first =
        "#{LightningWeb.Endpoint.url()}/api/projects?page=1&page_size=100"

      assert page == %{
               "data" => [
                 %{
                   "attributes" => %{
                     "name" => project.name,
                     "description" => nil
                   },
                   "id" => project.id,
                   "links" => %{
                     "self" =>
                       "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
                   },
                   "relationships" => %{},
                   "type" => "projects"
                 }
               ],
               "included" => [],
               "links" => %{
                 "first" => first,
                 "self" => first,
                 "last" => first,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "lists only the projects the token's user belongs to", %{conn: conn} do
      other_user = insert(:user)

      other_project =
        insert(:project, project_users: [%{user_id: other_user.id}])

      ids =
        conn
        |> assign_bearer(other_user)
        |> get(~p"/api/projects")
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])

      assert ids == [other_project.id]
    end
  end

  describe "showing, with a person's token" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "shows the project with its members, linking to it without the request's query",
         %{conn: conn, project: project, user: user} do
      response =
        conn
        |> get(~p"/api/projects/#{project.id}?foo=bar")
        |> json_response(200)

      url = "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"

      assert response == %{
               "data" => %{
                 "attributes" => %{
                   "name" => project.name,
                   "description" => nil,
                   "members" => [%{"email" => user.email, "role" => "editor"}]
                 },
                 "id" => project.id,
                 "links" => %{"self" => url},
                 "relationships" => %{},
                 "type" => "projects"
               },
               "included" => [],
               "links" => %{"self" => url}
             }
    end
  end

  describe "showing, with a service account that has projects:write" do
    setup %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      %{conn: conn}
    end

    test "shows a project it is not a member of, with its members", %{
      conn: conn
    } do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      conn = get(conn, ~p"/api/projects/#{project.id}")

      assert %{"id" => id, "attributes" => attributes} =
               json_response(conn, 200)["data"]

      assert id == project.id

      assert attributes == %{
               "name" => project.name,
               "description" => project.description,
               "members" => [%{"email" => owner.email, "role" => "owner"}]
             }
    end
  end
end
