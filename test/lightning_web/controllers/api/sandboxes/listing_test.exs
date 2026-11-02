defmodule LightningWeb.API.Sandboxes.ListingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    owner = insert(:user)
    parent = insert(:project, project_users: [%{user: owner, role: :owner}])

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     owner: owner,
     parent: parent}
  end

  defp entry(project) do
    %{
      "type" => "projects",
      "id" => project.id,
      "attributes" =>
        Map.merge(default_settings(), %{
          "name" => project.name,
          "description" => project.description
        }),
      "relationships" => %{},
      "links" => %{
        "self" => "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
      }
    }
  end

  defp page_url(parent, page, size) do
    "#{LightningWeb.Endpoint.url()}/api/projects/#{parent.id}/sandboxes?page=#{page}&page_size=#{size}"
  end

  describe "listing a project's sandboxes" do
    test "answers its direct sandboxes by name, leaving out those scheduled for deletion and their own sandboxes, on a session token",
         %{conn: conn, owner: owner, parent: parent} do
      zulu = insert(:project, parent: parent, name: "zulu")
      alpha = insert(:project, parent: parent, name: "alpha")
      insert(:project, parent: alpha, name: "nested")

      insert(:project,
        parent: parent,
        name: "going",
        scheduled_deletion: DateTime.utc_now()
      )

      insert(:project, parent: insert(:project), name: "elsewhere")

      conn =
        conn
        |> session_conn(owner)
        |> get(~p"/api/projects/#{parent.id}/sandboxes")

      assert json_response(conn, 200) == %{
               "data" => [entry(alpha), entry(zulu)],
               "included" => [],
               "links" => %{
                 "self" => page_url(parent, 1, 10),
                 "first" => page_url(parent, 1, 10),
                 "last" => page_url(parent, 1, 10),
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "pages them", %{conn: conn, owner: owner, parent: parent} do
      insert(:project, parent: parent, name: "alpha")
      bravo = insert(:project, parent: parent, name: "bravo")
      insert(:project, parent: parent, name: "charlie")

      conn =
        conn
        |> with_pat(owner)
        |> get(~p"/api/projects/#{parent.id}/sandboxes?page=2&page_size=1")

      assert json_response(conn, 200) == %{
               "data" => [entry(bravo)],
               "included" => [],
               "links" => %{
                 "self" => page_url(parent, 2, 1),
                 "first" => page_url(parent, 1, 1),
                 "last" => page_url(parent, 3, 1),
                 "next" => page_url(parent, 3, 1),
                 "prev" => page_url(parent, 1, 1)
               }
             }
    end

    test "is open to a viewer and to the service account with projects:write",
         %{conn: conn, parent: parent} do
      viewer = insert(:user)
      insert(:project_user, project: parent, user: viewer, role: :viewer)
      sandbox = insert(:project, parent: parent, name: "staging")
      {account_conn, _account} = with_service_account(conn, ["projects:write"])

      for caller <- [with_pat(conn, viewer), account_conn] do
        assert %{"data" => [listed]} =
                 caller
                 |> get(~p"/api/projects/#{parent.id}/sandboxes")
                 |> json_response(200)

        assert listed == entry(sandbox)
      end
    end
  end
end
