defmodule LightningWeb.API.Projects.ReplacingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.RaceHelpers
  import Lightning.Factories
  import Ecto.Query
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "replacing or creating, with a service account that has projects:write" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["projects:write"])
      %{conn: conn, account: account}
    end

    test "creates the project with its members and links to it without the request's query, and is not one of them",
         %{
           conn: conn,
           account: account
         } do
      id = Ecto.UUID.generate()
      members = four_members()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/projects/#{id}?foo=bar",
          Jason.encode!(%{
            "name" => "acme",
            "description" => "The acme project",
            "members" => members,
            "notify" => false
          })
        )

      response = json_response(conn, 201)
      self_link = "#{LightningWeb.Endpoint.url()}/api/projects/#{id}"

      assert %{
               "id" => ^id,
               "type" => "projects",
               "attributes" => %{
                 "name" => "acme",
                 "description" => "The acme project"
               },
               "links" => %{
                 "self" => ^self_link
               }
             } = response["data"]

      assert response["links"] == %{"self" => self_link}
      assert sorted_members(response) == Enum.sort_by(members, & &1["email"])

      assert members_of(id) ==
               members
               |> Enum.map(&{&1["email"], String.to_existing_atom(&1["role"])})
               |> Enum.sort()

      actors =
        from(a in Lightning.Auditing.Audit,
          where: a.item_id == ^id,
          select: {a.event, a.actor_id, a.actor_type}
        )
        |> Lightning.Repo.all()

      assert Enum.count(actors, &match?({"collaborator_added", _, _}, &1)) == 4
      assert {"created", account.uuid, :service_account} in actors

      assert Enum.all?(actors, fn {_, actor_id, actor_type} ->
               actor_id == account.uuid and actor_type == :service_account
             end)
    end

    test "emails the members it adds unless told not to", %{conn: conn} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        quiet_id = Ecto.UUID.generate()

        put_project(conn, quiet_id, %{
          "name" => "quiet",
          "members" => four_members(),
          "notify" => false
        })
        |> json_response(201)

        assert all_enqueued(worker: Lightning.Accounts.UserNotifier) == []

        put_project(conn, Ecto.UUID.generate(), %{
          "name" => "loud",
          "members" => four_members()
        })
        |> json_response(201)

        assert length(all_enqueued(worker: Lightning.Accounts.UserNotifier)) ==
                 4
      end)
    end

    test "matches a member's email without regard to case", %{conn: conn} do
      owner = insert(:user, email: "mixed.case@example.com")
      id = Ecto.UUID.generate()

      conn =
        put_project(conn, id, %{
          "name" => "acme",
          "members" => [
            %{"email" => "Mixed.CASE@example.com", "role" => "owner"}
          ]
        })

      assert json_response(conn, 201)
      assert members_of(id) == [{owner.email, :owner}]
    end

    test "a project another request deletes mid-replace answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)

      project =
        insert(:project,
          name: "before",
          project_users: [%{user: owner, role: :owner}]
        )

      delete_project_mid_save(project.id)

      conn
      |> put_project(project.id, %{
        "name" => "after",
        "members" => [%{"email" => owner.email, "role" => "owner"}]
      })
      |> assert_problem(409, :concurrent_edit, [])

      refute Lightning.Repo.reload(project)
    end

    test "replaces the name and description and keeps the members", %{
      conn: conn
    } do
      owner = insert(:user)

      project =
        insert(:project,
          name: "before",
          description: "old",
          project_users: [%{user: owner, role: :owner}]
        )

      conn =
        put_project(conn, project.id, %{
          "name" => "after",
          "description" => "new",
          "members" => [%{"email" => insert(:user).email, "role" => "owner"}]
        })

      response = json_response(conn, 200)

      assert response["data"]["attributes"] == %{
               "name" => "after",
               "description" => "new",
               "members" => [%{"email" => owner.email, "role" => "owner"}]
             }

      assert %{name: "after", description: "new"} =
               Lightning.Repo.reload!(project)

      assert members_of(project.id) == [{owner.email, :owner}]
    end
  end

  describe "creating, with a person's token" do
    test "a superuser creates a project", %{conn: conn} do
      conn = with_pat(conn, insert(:user, role: :superuser))
      id = Ecto.UUID.generate()

      conn =
        put_project(conn, id, %{"name" => "acme", "members" => four_members()})

      assert %{"id" => ^id} = json_response(conn, 201)["data"]
    end
  end
end
