defmodule LightningWeb.API.AuditEvents.ListingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers, only: [with_service_account: 2]

  @base ~U[2026-03-01 12:00:00Z]

  setup %{conn: conn} do
    superuser =
      insert(:user,
        role: :superuser,
        first_name: "Ada",
        last_name: "Lovelace",
        email: "ada@example.com"
      )

    %{
      conn:
        conn
        |> put_req_header("accept", "application/json")
        |> assign_bearer(superuser),
      superuser: superuser
    }
  end

  defp at(seconds), do: DateTime.add(@base, seconds, :second)

  defp list_url(query),
    do:
      "#{LightningWeb.Endpoint.url()}/api/audit_events?#{URI.encode_query(query)}"

  defp ids(conn), do: Enum.map(json_response(conn, 200)["data"], & &1["id"])

  describe "GET /api/audit_events" do
    test "a superuser lists every event newest first, each naming its actor, with credential bodies left out",
         %{conn: conn, superuser: superuser} do
      trigger = insert(:trigger, type: :webhook)
      repo_connection = insert(:project_repo_connection)

      by_user =
        insert(:audit,
          event: "updated",
          item_type: "project",
          actor_type: :user,
          actor_id: superuser.id,
          changes: %{
            before: %{"description" => "Malaria reporting"},
            after: %{"description" => "Malaria case reporting"}
          },
          inserted_at: at(5)
        )

      credential_created =
        insert(:audit,
          event: "created",
          item_type: "credential",
          actor_type: :user,
          actor_id: Ecto.UUID.generate(),
          changes: %{after: %{"name" => "dhis2"}},
          metadata: %{
            "credential_bodies" => %{"body:main" => "ZW5jcnlwdGVk"},
            "environments" => ["main"]
          },
          inserted_at: at(4)
        )

      by_service_account =
        insert(:audit,
          event: "token_issued",
          item_type: "service_account",
          actor_type: :service_account,
          actor_id: Ecto.UUID.generate(),
          changes: %{},
          metadata: %{"service_account_id" => "sa-thumbprint"},
          inserted_at: at(3)
        )

      by_trigger =
        insert(:audit,
          actor_type: :trigger,
          actor_id: trigger.id,
          inserted_at: at(2)
        )

      by_repo =
        insert(:audit,
          actor_type: :project_repo_connection,
          actor_id: repo_connection.id,
          inserted_at: at(1)
        )

      entry = fn audit, attributes ->
        %{
          "type" => "audit_events",
          "id" => audit.id,
          "attributes" =>
            Map.merge(
              %{
                "event" => audit.event,
                "item_type" => audit.item_type,
                "item_id" => audit.item_id,
                "actor_type" => to_string(audit.actor_type),
                "actor_id" => audit.actor_id,
                "changes" => %{
                  "before" => %{"stuff" => "bad"},
                  "after" => %{"stuff" => "good"}
                },
                "metadata" => %{},
                "inserted_at" => DateTime.to_iso8601(audit.inserted_at)
              },
              attributes
            ),
          "relationships" => %{},
          "links" => %{}
        }
      end

      assert conn |> get(~p"/api/audit_events") |> json_response(200) == %{
               "data" => [
                 entry.(by_user, %{
                   "actor_display" => "Ada Lovelace (ada@example.com)",
                   "changes" => %{
                     "before" => %{"description" => "Malaria reporting"},
                     "after" => %{"description" => "Malaria case reporting"}
                   }
                 }),
                 entry.(credential_created, %{
                   "actor_display" => "(User deleted)",
                   "changes" => %{
                     "before" => nil,
                     "after" => %{"name" => "dhis2"}
                   },
                   "metadata" => %{"environments" => ["main"]}
                 }),
                 entry.(by_service_account, %{
                   "actor_display" => "Service account (sa-thumbprint)",
                   "changes" => %{"before" => nil, "after" => nil},
                   "metadata" => %{"service_account_id" => "sa-thumbprint"}
                 }),
                 entry.(by_trigger, %{"actor_display" => "Webhook"}),
                 entry.(by_repo, %{"actor_display" => "GitHub"})
               ],
               "included" => [],
               "links" => %{
                 "self" => list_url(page: 1, page_size: 10),
                 "first" => list_url(page: 1, page_size: 10),
                 "last" => list_url(page: 1, page_size: 10),
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "a superuser's session token and the service account with audit:read list them too",
         %{conn: conn, superuser: superuser} do
      audit = insert(:audit, actor_type: :user, actor_id: superuser.id)
      {service_account, _account} = with_service_account(conn, ["audit:read"])

      for caller <- [session_conn(build_conn(), superuser), service_account] do
        assert ids(get(caller, ~p"/api/audit_events")) == [audit.id]
      end
    end

    test "each filter narrows the list, and the links carry the filters applied",
         %{conn: conn} do
      actor_id = Ecto.UUID.generate()
      item_id = Ecto.UUID.generate()

      match =
        insert(:audit,
          item_type: "workflow",
          item_id: item_id,
          event: "updated",
          actor_type: :user,
          actor_id: actor_id,
          inserted_at: at(0)
        )

      for {key, other} <- [
            item_type: "project",
            item_id: Ecto.UUID.generate(),
            event: "deleted",
            actor_id: Ecto.UUID.generate()
          ] do
        insert(
          :audit,
          Keyword.merge(
            [
              item_type: "workflow",
              item_id: item_id,
              event: "updated",
              actor_type: :user,
              actor_id: actor_id,
              inserted_at: at(0)
            ],
            [{key, other}]
          )
        )
      end

      insert(:audit,
        item_type: "workflow",
        actor_type: :user,
        actor_id: actor_id,
        inserted_at: at(-60)
      )

      insert(:audit,
        item_type: "workflow",
        actor_type: :user,
        actor_id: actor_id,
        inserted_at: at(60)
      )

      query = %{
        "item_type" => "workflow",
        "item_id" => item_id,
        "event" => "updated",
        "actor_id" => actor_id,
        "inserted_after" => "2026-03-01T11:59:00Z",
        "inserted_before" => "2026-03-01T12:01:00Z"
      }

      conn = get(conn, ~p"/api/audit_events?#{query}")

      assert ids(conn) == [match.id]

      assert json_response(conn, 200)["links"]["self"] ==
               list_url(
                 Map.merge(query, %{
                   "inserted_after" => "2026-03-01T11:59:00.000000Z",
                   "inserted_before" => "2026-03-01T12:01:00.000000Z",
                   "page" => 1,
                   "page_size" => 10
                 })
               )
    end

    test "pages newest first, in a fixed order within a second", %{conn: conn} do
      audits =
        for _ <- 1..3,
            do:
              insert(:audit,
                actor_type: :user,
                actor_id: Ecto.UUID.generate(),
                inserted_at: at(0)
              )

      expected = audits |> Enum.map(& &1.id) |> Enum.sort(:desc)

      pages =
        for page <- 1..3,
            do: ids(get(conn, ~p"/api/audit_events?page=#{page}&page_size=1"))

      assert List.flatten(pages) == expected
    end

    test "refuses every bad filter in one 400", %{conn: conn} do
      conn
      |> get(
        ~p"/api/audit_events?item_id=nope&actor_id=nope&inserted_after=yesterday"
      )
      |> assert_problem(400, :invalid_parameter, [
        %{"parameter" => "actor_id", "code" => "type", "detail" => "is invalid"},
        %{
          "parameter" => "inserted_after",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{"parameter" => "item_id", "code" => "type", "detail" => "is invalid"}
      ])
    end
  end

  describe "who may reach it" do
    test "anyone but a superuser or the service account is refused 403, filters or not",
         %{conn: conn} do
      member = insert(:user)
      insert(:project, project_users: [%{user: member, role: :owner}])
      insert(:audit, actor_type: :user, actor_id: member.id)

      for caller <- [
            assign_bearer(conn, member),
            session_conn(build_conn(), member)
          ],
          path <- [~p"/api/audit_events", ~p"/api/audit_events?item_id=nope"] do
        caller |> get(path) |> assert_problem(403, :forbidden, [])
      end
    end

    test "the service account without audit:read is refused for the scope",
         %{conn: conn} do
      {service_account, _account} =
        with_service_account(conn, ["users:read", "projects:write"])

      service_account
      |> get(~p"/api/audit_events")
      |> assert_refused_for_scope("audit:read")
    end
  end
end
