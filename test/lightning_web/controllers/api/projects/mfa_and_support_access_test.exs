defmodule LightningWeb.API.Projects.MfaAndSupportAccessTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Extensions.Message
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok,
     conn:
       conn
       |> put_req_header("accept", "application/json")
       |> put_req_header("content-type", "application/json")}
  end

  describe "requiring MFA" do
    test "an owner's session turns it on, answers with the project and records who did it",
         %{conn: conn} do
      owner = insert(:user, mfa_enabled: true)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      conn =
        conn
        |> session_conn(owner)
        |> put(
          ~p"/api/projects/#{project}/mfa_requirement",
          Jason.encode!(%{"requires_mfa" => true})
        )

      assert json_response(conn, 200)["data"]["attributes"] ==
               Map.merge(default_settings(), %{
                 "name" => project.name,
                 "description" => project.description,
                 "requires_mfa" => true,
                 "members" => [%{"email" => owner.email, "role" => "owner"}]
               })

      assert Repo.reload!(project).requires_mfa
      assert audit_events(project.id) == [{"requires_mfa_updated", owner.id}]
    end

    test "turning it on when the plan doesn't include it answers 402, while turning it off is never refused",
         %{conn: conn} do
      admin = insert(:user, mfa_enabled: true)

      for reason <- [:exceeds_limit, :mfa_not_in_plan] do
        Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
          %{type: :require_mfa}, _context ->
            {:error, reason, %Message{text: "Upgrade to require MFA"}}
        end)

        off = insert(:project, project_users: [%{user: admin, role: :admin}])

        conn
        |> with_pat(admin)
        |> put(
          ~p"/api/projects/#{off}/mfa_requirement",
          ~s({"requires_mfa": true})
        )
        |> assert_problem(402, :exceeds_limit, [])

        refute Repo.reload!(off).requires_mfa

        on =
          insert(:project,
            requires_mfa: true,
            project_users: [%{user: admin, role: :admin}]
          )

        conn
        |> with_pat(admin)
        |> put(
          ~p"/api/projects/#{on}/mfa_requirement",
          ~s({"requires_mfa": false})
        )
        |> json_response(200)

        refute Repo.reload!(on).requires_mfa
      end
    end

    test "a sandbox answers 422, since it copies the setting from its parent",
         %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      sandbox = insert(:sandbox, parent: insert(:project))

      conn
      |> put(
        ~p"/api/projects/#{sandbox}/mfa_requirement",
        ~s({"requires_mfa": true})
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/requires_mfa",
          "code" => "not_allowed",
          "detail" =>
            "can't be set on a sandbox, which copies it from the project it was created from"
        }
      ])

      refute Repo.reload!(sandbox).requires_mfa
    end
  end

  describe "allowing support access" do
    test "an admin's session turns it on, answers with the project and records who did it",
         %{conn: conn} do
      admin = insert(:user)
      project = insert(:project, project_users: [%{user: admin, role: :admin}])

      conn =
        conn
        |> session_conn(admin)
        |> put(
          ~p"/api/projects/#{project}/support_access",
          Jason.encode!(%{"allow_support_access" => true})
        )

      assert json_response(conn, 200)["data"]["attributes"][
               "allow_support_access"
             ]

      assert Repo.reload!(project).allow_support_access

      assert audit_events(project.id) == [
               {"allow_support_access_updated", admin.id}
             ]
    end

    test "the same body again changes nothing and records nothing", %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      project = insert(:project, allow_support_access: true)

      conn =
        put(
          conn,
          ~p"/api/projects/#{project}/support_access",
          ~s({"allow_support_access": true})
        )

      assert json_response(conn, 200)["data"]["attributes"][
               "allow_support_access"
             ] ==
               true

      assert audit_events(project.id) == []
    end
  end

  describe "refusals" do
    test "a body it can't apply answers 422 with every problem, on both routes",
         %{
           conn: conn
         } do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      for field <- ["requires_mfa", "allow_support_access"],
          {body, entries} <- [
            {%{}, [%{"code" => "required", "detail" => "can't be blank"}]},
            {%{field => "yes", "colour" => "red"},
             [
               %{"code" => "type", "detail" => "is invalid"},
               %{
                 "pointer" => "#/colour",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        entries = Enum.map(entries, &Map.put_new(&1, "pointer", "#/#{field}"))

        conn
        |> with_pat(owner)
        |> put(route(project, field), Jason.encode!(body))
        |> assert_problem(422, :invalid, entries)

        conn
        |> with_pat(owner)
        |> put(route(project, field), "[true]")
        |> assert_problem(400, :malformed, [])
      end

      project = Repo.reload!(project)
      refute project.requires_mfa or project.allow_support_access
    end
  end

  describe "stale writes" do
    test "a project another request deletes mid-write answers 409 concurrent_edit, on both routes",
         %{conn: conn} do
      owner = insert(:user, mfa_enabled: true)

      for field <- ["requires_mfa", "allow_support_access"] do
        project = insert(:project, project_users: [%{user: owner, role: :owner}])
        delete_project_mid_save(project.id)

        conn
        |> with_pat(owner)
        |> put(route(project, field), Jason.encode!(%{field => true}))
        |> assert_problem(409, :concurrent_edit, [])

        refute Repo.reload(project)
      end
    end
  end

  defp route(project, "requires_mfa"),
    do: ~p"/api/projects/#{project}/mfa_requirement"

  defp route(project, "allow_support_access"),
    do: ~p"/api/projects/#{project}/support_access"

  defp audit_events(project_id) do
    from(a in Lightning.Auditing.Audit,
      where: a.item_id == ^project_id,
      select: {a.event, a.actor_id}
    )
    |> Repo.all()
  end
end
