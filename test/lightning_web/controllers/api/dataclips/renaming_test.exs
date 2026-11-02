defmodule LightningWeb.API.Dataclips.RenamingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Auditing.Audit
  alias Lightning.Invocation.Dataclip

  setup %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :editor}])

    %{
      conn:
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> assign_bearer(user),
      user: user,
      project: project,
      dataclip:
        insert(:dataclip,
          project: project,
          type: :step_result,
          body: %{"x" => 1}
        )
    }
  end

  defp attributes(conn), do: json_response(conn, 200)["data"]["attributes"]

  describe "PATCH /api/dataclips/:id" do
    test "an editor names a dataclip and gets it back with its body, and the name is audited",
         %{conn: conn, user: user, dataclip: dataclip} do
      conn = patch(conn, ~p"/api/dataclips/#{dataclip.id}", %{name: "sample"})

      %Dataclip{updated_at: updated_at} = Repo.reload(dataclip)

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "dataclips",
                 "id" => dataclip.id,
                 "attributes" => %{
                   "name" => "sample",
                   "type" => "step_result",
                   "project_id" => dataclip.project_id,
                   "wiped_at" => nil,
                   "inserted_at" => DateTime.to_iso8601(dataclip.inserted_at),
                   "updated_at" => DateTime.to_iso8601(updated_at),
                   "body" => %{"x" => 1}
                 },
                 "relationships" => %{},
                 "links" => %{
                   "self" =>
                     "#{LightningWeb.Endpoint.url()}/api/dataclips/#{dataclip.id}"
                 }
               },
               "included" => [],
               "links" => %{
                 "self" =>
                   "#{LightningWeb.Endpoint.url()}/api/dataclips/#{dataclip.id}"
               }
             }

      assert [%Audit{event: "label_created", actor_id: actor_id}] =
               Repo.all(Audit)

      assert actor_id == user.id
    end

    test "a session token names it, with the session's CSRF token", %{
      user: user,
      dataclip: dataclip
    } do
      conn =
        build_conn()
        |> session_conn(user)
        |> patch(~p"/api/dataclips/#{dataclip.id}", %{name: "sample"})

      assert %{"name" => "sample"} = attributes(conn)
      assert %Dataclip{name: "sample"} = Repo.reload(dataclip)
    end

    test "null removes the name, and a body without one changes nothing", %{
      conn: conn,
      project: project
    } do
      dataclip = insert(:dataclip, project: project, name: "sample")

      assert %{"name" => "sample"} =
               conn
               |> patch(~p"/api/dataclips/#{dataclip.id}", %{})
               |> attributes()

      assert %{"name" => nil} =
               conn
               |> patch(~p"/api/dataclips/#{dataclip.id}", %{name: nil})
               |> attributes()

      assert %Dataclip{name: nil} = Repo.reload(dataclip)

      assert ["label_deleted"] = Audit |> Repo.all() |> Enum.map(& &1.event)
    end

    test "refuses a name another dataclip in the project has", %{
      conn: conn,
      project: project,
      dataclip: dataclip
    } do
      insert(:dataclip, project: project, name: "sample")

      conn
      |> patch(~p"/api/dataclips/#{dataclip.id}", %{name: "sample"})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "taken",
          "detail" => "has already been taken"
        }
      ])

      assert %Dataclip{name: nil} = Repo.reload(dataclip)
    end

    test "refuses unknown keys together with a bad name, and a name too long",
         %{conn: conn, dataclip: dataclip} do
      for {body, entries} <- [
            {%{name: 7, body: %{}},
             [
               %{
                 "pointer" => "#/body",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/name",
                 "code" => "type",
                 "detail" => "is invalid"
               }
             ]},
            {%{name: String.duplicate("a", 256)},
             [
               %{
                 "pointer" => "#/name",
                 "code" => "too_long",
                 "detail" => "should be at most 255 character(s)"
               }
             ]}
          ] do
        conn
        |> patch(~p"/api/dataclips/#{dataclip.id}", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert %Dataclip{name: nil} = Repo.reload(dataclip)
    end

    test "refuses a body that isn't a JSON object", %{
      conn: conn,
      dataclip: dataclip
    } do
      conn
      |> patch(~p"/api/dataclips/#{dataclip.id}", Jason.encode!(["sample"]))
      |> assert_problem(400, :malformed, [])
    end
  end

  describe "stale writes" do
    test "a dataclip another request deletes mid-rename answers 409 concurrent_edit",
         %{conn: conn, dataclip: dataclip} do
      delete_after_second_read(dataclip.id)

      conn
      |> patch(~p"/api/dataclips/#{dataclip.id}", %{name: "sample"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(dataclip)
      assert Repo.all(Audit) == []
    end
  end

  # The route reads the dataclip twice, for its project and then in it, before
  # it writes. Deleting after the first read would answer the lookup instead.
  defp delete_after_second_read(id) do
    handler = {__MODULE__, make_ref()}
    dumped = Ecto.UUID.dump!(id)
    test_pid = self()

    :telemetry.attach(
      handler,
      [:lightning, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == test_pid and meta.source == "dataclips" and
             dumped in List.flatten(meta.params) do
          reads = Process.get(handler, 0) + 1
          Process.put(handler, reads)

          if reads == 2,
            do: Repo.query!("DELETE FROM dataclips WHERE id = $1", [dumped])
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end
end
