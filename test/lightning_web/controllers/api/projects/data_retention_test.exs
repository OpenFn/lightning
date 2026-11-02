defmodule LightningWeb.API.Projects.DataRetentionTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers
  import Swoosh.TestAssertions

  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok,
     conn:
       conn
       |> put_req_header("accept", "application/json")
       |> put_req_header("content-type", "application/json")}
  end

  describe "setting data retention" do
    test "an admin's session sets the policy and both periods, answers with the project, and emails the owners and admins",
         %{conn: conn} do
      [owner, admin, editor] = insert_list(3, :user)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: editor, role: :editor}
          ]
        )

      conn =
        conn
        |> session_conn(admin)
        |> put(
          ~p"/api/projects/#{project}/data_retention",
          Jason.encode!(%{
            "retention_policy" => "retain_with_errors",
            "history_retention_period" => 90,
            "dataclip_retention_period" => 30
          })
        )

      url = "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
      response = json_response(conn, 200)

      assert response == %{
               "data" => %{
                 "type" => "projects",
                 "id" => project.id,
                 "attributes" =>
                   Map.merge(default_settings(), %{
                     "name" => project.name,
                     "description" => project.description,
                     "retention_policy" => "retain_with_errors",
                     "history_retention_period" => 90,
                     "dataclip_retention_period" => 30,
                     "members" => response["data"]["attributes"]["members"]
                   }),
                 "relationships" => %{},
                 "links" => %{"self" => url}
               },
               "included" => [],
               "links" => %{"self" => url <> "/data_retention"}
             }

      assert Enum.sort_by(
               response["data"]["attributes"]["members"],
               & &1["role"]
             ) ==
               [
                 %{"email" => admin.email, "role" => "admin"},
                 %{"email" => editor.email, "role" => "editor"},
                 %{"email" => owner.email, "role" => "owner"}
               ]

      assert %{
               retention_policy: :retain_with_errors,
               history_retention_period: 90,
               dataclip_retention_period: 30
             } = Repo.reload!(project)

      assert audit_events(project.id) == [
               {"dataclip_retention_period_updated", admin.id},
               {"history_retention_period_updated", admin.id}
             ]

      subject = "The data retention policy for #{project.name} has been modified"

      assert sent_to(subject) == Enum.sort([owner.email, admin.email])
    end

    test "the same body twice changes nothing the second time and sends no email",
         %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])

      project =
        insert(:project,
          retention_policy: :retain_all,
          history_retention_period: 30,
          dataclip_retention_period: 7,
          project_users: [%{user: insert(:user), role: :owner}]
        )

      conn =
        put(
          conn,
          ~p"/api/projects/#{project}/data_retention",
          Jason.encode!(%{
            "retention_policy" => "retain_all",
            "history_retention_period" => 30,
            "dataclip_retention_period" => 7
          })
        )

      assert json_response(conn, 200)["data"]["attributes"][
               "history_retention_period"
             ] ==
               30

      assert audit_events(project.id) == []
      assert_no_email_sent()
    end

    test "erase_all and a missing history period each clear the dataclip period",
         %{conn: conn} do
      owner = insert(:user)

      for {body, expected} <- [
            {%{
               "retention_policy" => "erase_all",
               "history_retention_period" => 30,
               "dataclip_retention_period" => 7
             }, {:erase_all, 30, nil}},
            {%{
               "retention_policy" => "retain_all",
               "dataclip_retention_period" => 7
             }, {:retain_all, nil, nil}}
          ] do
        project =
          insert(:project,
            history_retention_period: 30,
            dataclip_retention_period: 14,
            project_users: [%{user: owner, role: :owner}]
          )

        conn
        |> with_pat(owner)
        |> put(~p"/api/projects/#{project}/data_retention", Jason.encode!(body))
        |> json_response(200)

        project = Repo.reload!(project)

        assert {project.retention_policy, project.history_retention_period,
                project.dataclip_retention_period} == expected
      end
    end
  end

  describe "refusals" do
    setup do
      owner = insert(:user)

      project =
        insert(:project,
          history_retention_period: 30,
          project_users: [%{user: owner, role: :owner}]
        )

      %{owner: owner, project: project}
    end

    test "a body it can't apply answers 422 with every problem and changes nothing",
         %{conn: conn, owner: owner, project: project} do
      for {body, entries} <- [
            {%{
               "retention_policy" => "retain_all",
               "history_retention_period" => 14,
               "dataclip_retention_period" => 30
             },
             [
               %{
                 "pointer" => "#/dataclip_retention_period",
                 "code" => "out_of_range",
                 "detail" =>
                   "dataclip retention period must be less or equal to the history retention period"
               }
             ]},
            {%{
               "history_retention_period" => 8,
               "retention_policy" => "sideways",
               "colour" => "red"
             },
             [
               %{
                 "pointer" => "#/colour",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/history_retention_period",
                 "code" => "not_allowed",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/retention_policy",
                 "code" => "not_allowed",
                 "detail" => "is invalid"
               }
             ]},
            {%{"history_retention_period" => "a month"},
             [
               %{
                 "pointer" => "#/retention_policy",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/history_retention_period",
                 "code" => "type",
                 "detail" => "is invalid"
               }
             ]}
          ] do
        conn
        |> with_pat(owner)
        |> put(~p"/api/projects/#{project}/data_retention", Jason.encode!(body))
        |> assert_problem(422, :invalid, entries)
      end

      assert Repo.reload!(project).history_retention_period == 30
    end

    test "a period the plan doesn't allow answers 422, unless it is the one the project already has",
         %{conn: conn, owner: owner, project: project} do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :get_data_retention_periods,
        fn _context -> [7, 14] end
      )

      conn
      |> with_pat(owner)
      |> put(
        ~p"/api/projects/#{project}/data_retention",
        Jason.encode!(%{
          "retention_policy" => "retain_all",
          "history_retention_period" => 90,
          "dataclip_retention_period" => 14
        })
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/history_retention_period",
          "code" => "not_allowed",
          "detail" => "is not a retention period the plan allows"
        }
      ])

      conn
      |> with_pat(owner)
      |> put(
        ~p"/api/projects/#{project}/data_retention",
        Jason.encode!(%{
          "retention_policy" => "retain_all",
          "history_retention_period" => 30,
          "dataclip_retention_period" => 14
        })
      )
      |> json_response(200)

      assert Repo.reload!(project).dataclip_retention_period == 14
    end

    test "a body that isn't a JSON object answers 400 malformed", %{
      conn: conn,
      owner: owner,
      project: project
    } do
      conn
      |> with_pat(owner)
      |> put(~p"/api/projects/#{project}/data_retention", "[1]")
      |> assert_problem(400, :malformed, [])
    end
  end

  describe "stale writes" do
    test "a project another request deletes mid-write answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      delete_project_mid_save(project.id)

      conn
      |> with_pat(owner)
      |> put(
        ~p"/api/projects/#{project}/data_retention",
        Jason.encode!(%{"retention_policy" => "erase_all"})
      )
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(project)
    end
  end

  defp sent_to(subject) do
    for(
      {:email, %{subject: ^subject, to: [{_name, address}]}} <- emails(),
      do: address
    )
    |> Enum.sort()
  end

  defp emails do
    receive do
      {:email, _email} = message -> [message | emails()]
    after
      0 -> []
    end
  end

  defp audit_events(project_id) do
    from(a in Lightning.Auditing.Audit,
      where: a.item_id == ^project_id,
      select: {a.event, a.actor_id},
      order_by: a.event
    )
    |> Repo.all()
  end
end
