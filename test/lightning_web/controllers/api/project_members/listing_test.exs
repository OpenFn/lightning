defmodule LightningWeb.API.ProjectMembers.ListingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectMembersHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "listing" do
    test "a viewer's session lists every member by first name, with their notifications",
         %{conn: conn} do
      ada = insert(:user, first_name: "Ada")
      grace = insert(:user, first_name: "Grace")
      viewer = insert(:user, first_name: "Zed")

      project =
        insert(:project,
          project_users: [
            %{user: grace, role: :editor, failure_alert: true, digest: :weekly},
            %{user: viewer, role: :viewer},
            %{user: ada, role: :owner}
          ]
        )

      conn =
        conn |> session_conn(viewer) |> get(~p"/api/projects/#{project}/members")

      first =
        "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/members?page=1&page_size=10"

      assert json_response(conn, 200) == %{
               "data" => [
                 member_json(project.id, ada, :owner),
                 member_json(project.id, grace, :editor,
                   failure_alert: true,
                   digest: :weekly
                 ),
                 member_json(project.id, viewer, :viewer)
               ],
               "included" => [],
               "links" => %{
                 "self" => first,
                 "first" => first,
                 "last" => first,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "pages, with links carrying the page size applied and no other query parameter",
         %{conn: conn} do
      users = for name <- ~w(Ada Bea Cy), do: insert(:user, first_name: name)

      project =
        insert(:project,
          project_users: Enum.map(users, &%{user: &1, role: :editor})
        )

      {conn, _account} = with_service_account(conn, ["projects:write"])

      response =
        conn
        |> get(~p"/api/projects/#{project}/members?page=2&page_size=1&foo=bar")
        |> json_response(200)

      link =
        &"#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/members?page=#{&1}&page_size=1"

      assert Enum.map(response["data"], & &1["id"]) == [Enum.at(users, 1).id]

      assert response["links"] == %{
               "self" => link.(2),
               "first" => link.(1),
               "last" => link.(3),
               "next" => link.(3),
               "prev" => link.(1)
             }
    end

    test "a support user may list a project that allows support access, and isn't among its members",
         %{conn: conn} do
      support = insert(:user, support_user: true)
      owner = insert(:user)

      project =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: owner, role: :owner}]
        )

      response =
        conn
        |> with_pat(support)
        |> get(~p"/api/projects/#{project}/members")
        |> json_response(200)

      assert response["data"] == [member_json(project.id, owner, :owner)]
    end
  end
end
