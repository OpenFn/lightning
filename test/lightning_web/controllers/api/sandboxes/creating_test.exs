defmodule LightningWeb.API.Sandboxes.CreatingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import LightningWeb.ApiSandboxesHelpers
  import Lightning.Factories

  alias Lightning.Extensions.Message
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Projects.Project
  alias Lightning.Repo

  setup %{conn: conn} do
    owner = insert(:user, email: "owner@example.com")
    editor = insert(:user, email: "editor@example.com")

    parent =
      insert(:project,
        name: "malaria",
        project_users: [
          %{user: owner, role: :owner},
          %{user: editor, role: :editor}
        ]
      )

    insert(:simple_workflow, project: parent, name: "intake")

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     owner: owner,
     editor: editor,
     parent: parent}
  end

  defp show_body(id, name, members, self) do
    %{
      "data" => %{
        "type" => "projects",
        "id" => id,
        "attributes" =>
          Map.merge(default_settings(), %{
            "name" => name,
            "description" => nil,
            "members" => members
          }),
        "relationships" => %{},
        "links" => %{
          "self" => "#{LightningWeb.Endpoint.url()}/api/projects/#{id}"
        }
      },
      "included" => [],
      "links" => %{"self" => self}
    }
  end

  defp sorted_body(body),
    do:
      update_in(
        body,
        ["data", "attributes", "members"],
        &Enum.sort_by(&1, fn member -> member["email"] end)
      )

  describe "creating a sandbox" do
    test "an editor creates it under the path's id on a session token, becoming its owner, with the parent's owner as an admin and workflows cloned with triggers disabled",
         %{conn: conn, editor: editor, parent: parent} do
      id = Ecto.UUID.generate()

      conn =
        conn
        |> session_conn(editor)
        |> put_sandbox(parent.id, id, %{
          "name" => "staging",
          "color" => "#336699",
          "env" => "staging"
        })

      self =
        "#{LightningWeb.Endpoint.url()}/api/projects/#{parent.id}/sandboxes/#{id}"

      assert sorted_body(json_response(conn, 201)) ==
               show_body(
                 id,
                 "staging",
                 [
                   %{"email" => "editor@example.com", "role" => "owner"},
                   %{"email" => "owner@example.com", "role" => "admin"}
                 ],
                 self
               )

      sandbox =
        Repo.get!(Project, id) |> Repo.preload(workflows: :triggers)

      assert {sandbox.parent_id, sandbox.color, sandbox.env} ==
               {parent.id, "#336699", "staging"}

      assert [%{name: "intake", triggers: [%{enabled: false}]}] =
               sandbox.workflows
    end

    test "a repeat with the same id answers 200 with the sandbox unchanged",
         %{conn: conn, editor: editor, parent: parent} do
      id = Ecto.UUID.generate()
      caller = with_pat(conn, editor)
      put_sandbox(caller, parent.id, id, %{"name" => "staging"})

      conn = put_sandbox(caller, parent.id, id, %{"name" => "staging"})

      assert %{"data" => %{"id" => ^id, "attributes" => %{"name" => "staging"}}} =
               json_response(conn, 200)

      assert Repo.aggregate(
               from(p in Project, where: p.parent_id == ^parent.id),
               :count
             ) == 1
    end

    test "a body it can't use answers one 422 with every problem in it, and nothing is created",
         %{conn: conn, editor: editor, parent: parent} do
      insert(:project, parent: parent, name: "taken")
      caller = with_pat(conn, editor)

      for {body, entries} <- [
            {%{"color" => "blue", "env" => "Not A Slug", "extra" => 1},
             [
               %{
                 "pointer" => "#/extra",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/name",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/color",
                 "code" => "format",
                 "detail" => "must be hex"
               },
               %{
                 "pointer" => "#/env",
                 "code" => "format",
                 "detail" => "must be a short slug"
               }
             ]},
            {%{"name" => "taken"},
             [
               %{
                 "pointer" => "#/name",
                 "code" => "taken",
                 "detail" => "has already been taken"
               }
             ]},
            {%{"name" => "new", "dataclip_ids" => [Ecto.UUID.generate()]},
             [
               %{
                 "pointer" => "#/dataclip_ids",
                 "code" => "not_found",
                 "detail" =>
                   "names a dataclip the project can't copy into a sandbox"
               }
             ]},
            {%{"name" => "new", "id" => Ecto.UUID.generate()},
             [
               %{
                 "pointer" => "#/id",
                 "code" => "mismatch",
                 "detail" => "does not match the id in the path"
               }
             ]}
          ] do
        id = Ecto.UUID.generate()

        caller
        |> put_sandbox(parent.id, id, body)
        |> assert_problem(422, :invalid, entries)

        refute Repo.get(Project, id)
      end
    end

    test "a parent already as deep as the instance allows answers 422 at the path's project",
         %{conn: conn, editor: editor, parent: parent} do
      Mox.stub(Lightning.MockConfig, :max_sandbox_nesting_depth, fn -> 0 end)
      id = Ecto.UUID.generate()

      conn
      |> with_pat(editor)
      |> put_sandbox(parent.id, id, %{"name" => "staging"})
      |> assert_problem(422, :invalid, [
        %{
          "path" => "project_id",
          "code" => "not_allowed",
          "detail" => "is already as deeply nested as this instance allows"
        }
      ])

      refute Repo.get(Project, id)
    end

    test "a plan with no room for another sandbox answers 402, after the body is checked",
         %{conn: conn, editor: editor, parent: parent} do
      caller = with_pat(conn, editor)

      for reason <- [:too_many_sandboxes, :exceeds_limit] do
        Mox.stub(MockUsageLimiter, :limit_action, fn
          %{type: :new_sandbox}, _context ->
            {:error, reason, %Message{text: "No room"}}

          _action, _context ->
            :ok
        end)

        caller
        |> put_sandbox(parent.id, Ecto.UUID.generate(), %{"name" => "staging"})
        |> assert_problem(402, :exceeds_limit, [])

        caller
        |> put_sandbox(parent.id, Ecto.UUID.generate(), %{})
        |> assert_problem(422, :invalid, [
          %{
            "pointer" => "#/name",
            "code" => "required",
            "detail" => "can't be blank"
          }
        ])
      end

      refute Repo.exists?(from(p in Project, where: p.parent_id == ^parent.id))
    end
  end

  describe "stale writes" do
    test "a sandbox another request creates under the id mid-write is met as a repeat",
         %{conn: conn, editor: editor, parent: parent} do
      id = Ecto.UUID.generate()

      Lightning.RaceHelpers.after_first_query("projects", id, fn _id ->
        insert(:project,
          id: id,
          parent: parent,
          name: "theirs",
          project_users: [%{user: editor, role: :owner}]
        )
      end)

      conn =
        conn
        |> with_pat(editor)
        |> put_sandbox(parent.id, id, %{"name" => "mine"})

      assert %{"data" => %{"id" => ^id, "attributes" => %{"name" => "theirs"}}} =
               json_response(conn, 200)

      assert Repo.get!(Project, id).name == "theirs"
    end
  end
end
