defmodule LightningWeb.API.Dataclips.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :viewer}])

    %{
      conn:
        conn
        |> put_req_header("accept", "application/json")
        |> assign_bearer(user),
      user: user,
      project: project
    }
  end

  defp self_link(dataclip),
    do: "#{LightningWeb.Endpoint.url()}/api/dataclips/#{dataclip.id}"

  defp document(dataclip, attributes) do
    %{
      "data" => %{
        "type" => "dataclips",
        "id" => dataclip.id,
        "attributes" =>
          Map.merge(
            %{
              "name" => dataclip.name,
              "type" => to_string(dataclip.type),
              "project_id" => dataclip.project_id,
              "wiped_at" => nil,
              "inserted_at" => DateTime.to_iso8601(dataclip.inserted_at),
              "updated_at" => DateTime.to_iso8601(dataclip.updated_at)
            },
            attributes
          ),
        "relationships" => %{},
        "links" => %{"self" => self_link(dataclip)}
      },
      "included" => [],
      "links" => %{"self" => self_link(dataclip)}
    }
  end

  describe "GET /api/dataclips/:id" do
    test "a project member reads a saved input and its body as an object, linked without the request's query",
         %{conn: conn, project: project} do
      dataclip =
        insert(:dataclip,
          project: project,
          type: :saved_input,
          name: "patient-sample",
          body: %{"data" => %{"patients" => [1, 2]}}
        )

      assert conn
             |> get(~p"/api/dataclips/#{dataclip.id}?foo=bar")
             |> json_response(200) ==
               document(dataclip, %{
                 "body" => %{"data" => %{"patients" => [1, 2]}}
               })
    end

    test "a session token reads it the same way", %{
      user: user,
      project: project
    } do
      dataclip =
        insert(:dataclip, project: project, type: :global, body: %{"a" => 1})

      assert build_conn()
             |> session_conn(user)
             |> get(~p"/api/dataclips/#{dataclip.id}")
             |> json_response(200) ==
               document(dataclip, %{"body" => %{"a" => 1}})
    end

    test "an http_request body comes with its request, and the webhook's credentials scrubbed out",
         %{conn: conn, project: project} do
      workflow = insert(:workflow, project: project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic,
          username: "webhook_user",
          password: "webhook_secret_pass"
        )

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :webhook,
          webhook_auth_methods: [auth_method]
        )

      dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: %{"password" => "webhook_secret_pass", "data" => "payload"},
          request: %{"headers" => %{"x-key" => "plain"}}
        )

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

      assert conn
             |> get(~p"/api/dataclips/#{dataclip.id}")
             |> json_response(200) ==
               document(dataclip, %{
                 "body" => %{
                   "data" => %{"password" => "***", "data" => "payload"},
                   "request" => %{"headers" => %{"x-key" => "plain"}}
                 }
               })
    end

    test "a step's output has the credentials of its run scrubbed, and a number holding a secret becomes a string, so the body stays JSON",
         %{conn: conn, user: user, project: project} do
      credential =
        insert(:credential, user: user)
        |> with_body(%{body: %{"pin" => 123_456, "key" => "55"}})

      job =
        insert(:job,
          workflow: insert(:workflow, project: project),
          project_credential:
            insert(:project_credential, credential: credential, project: project)
        )

      dataclip =
        insert(:dataclip,
          project: project,
          type: :step_result,
          body: %{"pin" => 123_456, "near" => 125_534, "ok" => true, "n" => 7}
        )

      step =
        insert(:step,
          job: job,
          output_dataclip: dataclip,
          started_at: DateTime.utc_now()
        )

      run =
        insert(:run,
          work_order:
            build(:workorder,
              workflow: job.workflow,
              dataclip: build(:dataclip, project: project)
            ),
          dataclip: build(:dataclip, project: project),
          starting_job: job
        )

      insert(:run_step, run: run, step: step)

      assert conn
             |> get(~p"/api/dataclips/#{dataclip.id}")
             |> json_response(200) ==
               document(dataclip, %{
                 "body" => %{
                   "pin" => "***",
                   "near" => "12***34",
                   "ok" => true,
                   "n" => 7
                 }
               })
    end

    test "a wiped dataclip says when, and its body's contents are null", %{
      conn: conn,
      project: project
    } do
      wiped_at = ~U[2026-01-01 00:00:00Z]

      step_result =
        insert(:dataclip,
          project: project,
          type: :step_result,
          body: nil,
          wiped_at: wiped_at
        )

      http_request =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: nil,
          request: nil,
          wiped_at: wiped_at
        )

      for {dataclip, body} <- [
            {step_result, nil},
            {http_request, %{"data" => nil, "request" => nil}}
          ] do
        assert conn
               |> get(~p"/api/dataclips/#{dataclip.id}")
               |> json_response(200) ==
                 document(dataclip, %{
                   "wiped_at" => "2026-01-01T00:00:00Z",
                   "body" => body
                 })
      end
    end
  end
end
