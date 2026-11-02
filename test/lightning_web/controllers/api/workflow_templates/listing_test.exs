defmodule LightningWeb.API.WorkflowTemplates.ListingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    %{
      conn: put_req_header(conn, "accept", "application/json"),
      user: insert(:user)
    }
  end

  defp full_url(path), do: "#{LightningWeb.Endpoint.url()}#{path}"

  describe "listing templates" do
    test "anyone on a session token gets every template by name",
         %{conn: conn, user: user} do
      second =
        insert(:workflow_template,
          name: "b template",
          description: nil,
          tags: []
        )

      first = insert(:workflow_template, name: "a template")
      page_one = full_url("/api/workflow_templates?page=1&page_size=10")

      conn = conn |> session_conn(user) |> get(~p"/api/workflow_templates")

      assert json_response(conn, 200) == %{
               "data" =>
                 for template <- [first, second] do
                   %{
                     "id" => template.id,
                     "name" => template.name,
                     "description" => template.description,
                     "tags" => template.tags,
                     "workflow_id" => template.workflow_id,
                     "code" => template.code
                   }
                 end,
               "links" => %{
                 "self" => page_one,
                 "first" => page_one,
                 "last" => page_one,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "q searches the name and description without regard to case, and tags keeps templates carrying every tag given",
         %{conn: conn, user: user} do
      insert(:workflow_template,
        name: "DHIS2 to FHIR",
        description: "Moves events",
        tags: ["dhis2", "fhir"]
      )

      insert(:workflow_template,
        name: "Kobo sync",
        description: "Copies dhis2 data",
        tags: ["kobo", "dhis2"]
      )

      insert(:workflow_template,
        name: "100% match_",
        description: nil,
        tags: []
      )

      conn = assign_bearer(conn, user)

      for {query, expected} <- [
            {%{q: "dhis2"}, ["DHIS2 to FHIR", "Kobo sync"]},
            {%{q: "EVENTS"}, ["DHIS2 to FHIR"]},
            {%{q: "%"}, ["100% match_"]},
            {%{q: "_"}, ["100% match_"]},
            {%{q: ""}, ["100% match_", "DHIS2 to FHIR", "Kobo sync"]},
            {%{tags: "dhis2"}, ["DHIS2 to FHIR", "Kobo sync"]},
            {%{tags: "dhis2,fhir"}, ["DHIS2 to FHIR"]},
            {%{tags: ","}, ["100% match_", "DHIS2 to FHIR", "Kobo sync"]},
            {%{q: "sync", tags: "fhir"}, []}
          ] do
        body =
          conn
          |> get(~p"/api/workflow_templates?#{query}")
          |> json_response(200)

        assert Enum.map(body["data"], & &1["name"]) == expected,
               "for #{inspect(query)}"
      end
    end

    test "the links carry the filters applied and the page", %{
      conn: conn,
      user: user
    } do
      for name <- ["a", "b", "c"],
          do: insert(:workflow_template, name: name, tags: ["x"])

      # An empty q filters nothing, so the links leave it out.
      page = fn number ->
        full_url("/api/workflow_templates?page=#{number}&page_size=1&tags=x")
      end

      body =
        conn
        |> assign_bearer(user)
        |> get(~p"/api/workflow_templates?page=2&page_size=1&q=&tags=x")
        |> json_response(200)

      assert Enum.map(body["data"], & &1["name"]) == ["b"]

      assert body["links"] == %{
               "self" => page.(2),
               "first" => page.(1),
               "last" => page.(3),
               "next" => page.(3),
               "prev" => page.(1)
             }
    end

    test "a q that isn't one string answers 400 invalid_parameter", %{
      conn: conn,
      user: user
    } do
      conn
      |> assign_bearer(user)
      |> get("/api/workflow_templates?q[]=a")
      |> assert_problem(400, :invalid_parameter, [
        %{"parameter" => "q", "code" => "type", "detail" => "is invalid"}
      ])
    end
  end
end
