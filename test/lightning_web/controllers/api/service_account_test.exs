defmodule LightningWeb.API.ServiceAccountTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Ecto.Query
  import Lightning.ServiceAccountHelpers
  import LightningWeb.API.ProblemHelpers

  setup %{conn: conn} do
    {conn, _account} =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> with_service_account(["projects:write", "credentials:write"])

    project = insert(:project, name: "a-project")
    run_in(insert(:project, name: "b-project"))

    project |> run_in() |> Map.merge(%{conn: conn, project: project})
  end

  test "lists every project, though it is a member of none", %{conn: conn} do
    every =
      Repo.all(
        from(p in Lightning.Projects.Project, order_by: p.name, select: p.id)
      )

    assert ids(get(conn, ~p"/api/projects"), "data") == every
  end

  test "lists the workflows and jobs of every project", %{conn: conn} do
    for {path, key, schema} <- [
          {~p"/api/workflows", "workflows", Lightning.Workflows.Workflow},
          {~p"/api/jobs", "data", Lightning.Workflows.Job}
        ] do
      every = Repo.all(from(r in schema, select: r.id))

      assert length(every) > 1, path
      assert MapSet.new(ids(get(conn, path), key)) == MapSet.new(every), path
    end
  end

  test "must name a project to list work orders, runs or log lines, and lists that project's",
       %{conn: conn, project: project} = context do
    required = %{
      "parameter" => "project_id",
      "code" => "required",
      "detail" => "can't be blank"
    }

    for {top, bad_filter, bad_entry, record} <- [
          {"/api/work_orders", "state=bogus",
           %{
             "parameter" => "state",
             "code" => "not_allowed",
             "detail" => "has an invalid entry"
           }, :work_order},
          {"/api/runs", "state=bogus",
           %{
             "parameter" => "state",
             "code" => "not_allowed",
             "detail" => "has an invalid entry"
           }, :run},
          {"/api/log_lines", "level=bogus",
           %{
             "parameter" => "level",
             "code" => "not_allowed",
             "detail" => "is invalid"
           }, :log_line}
        ] do
      conn |> get(top) |> assert_problem(400, :invalid_parameter, [required])

      conn
      |> get("#{top}?#{bad_filter}")
      |> assert_problem(400, :invalid_parameter, [bad_entry, required])

      assert ids(get(conn, "#{top}?project_id=#{project.id}"), "data") == [
               context[record].id
             ],
             top
    end
  end

  test "lists and shows the records of a project it is not a member of",
       %{conn: conn, project: project} = context do
    for {path, key, record} <- [
          {~p"/api/projects/#{project.id}/workflows", "workflows", :workflow},
          {~p"/api/projects/#{project.id}/jobs", "data", :job},
          {~p"/api/projects/#{project.id}/work_orders", "data", :work_order},
          {~p"/api/projects/#{project.id}/runs", "data", :run}
        ] do
      assert ids(get(conn, path), key) == [context[record].id], path
    end

    for {path, key, record} <- [
          {~p"/api/workflows/#{context.workflow.id}", "workflow", :workflow},
          {~p"/api/projects/#{project.id}/workflows/#{context.workflow.id}",
           "workflow", :workflow},
          {~p"/api/jobs/#{context.job.id}", "data", :job},
          {~p"/api/projects/#{project.id}/jobs/#{context.job.id}", "data", :job},
          {~p"/api/work_orders/#{context.work_order.id}", "data", :work_order},
          {~p"/api/projects/#{project.id}/work_orders/#{context.work_order.id}",
           "data", :work_order},
          {~p"/api/runs/#{context.run.id}", "data", :run},
          {~p"/api/projects/#{project.id}/runs/#{context.run.id}", "data", :run}
        ] do
      assert %{"id" => id} = json_response(get(conn, path), 200)[key], path
      assert id == context[record].id, path
    end
  end

  test "describes a project for provisioning, as JSON and as YAML",
       %{conn: conn, project: project} do
    assert json_response(get(conn, ~p"/api/provision/#{project.id}"), 200)[
             "data"
           ]["id"] == project.id

    assert conn
           |> get(~p"/api/provision/yaml?id=#{project.id}")
           |> response(200) =~ "name: a-project"
  end

  test "creates and updates a workflow in a project it is not a member of",
       %{conn: conn, project: project, workflow: workflow} do
    created =
      conn
      |> post(
        ~p"/api/projects/#{project.id}/workflows",
        Jason.encode!(
          build(:simple_workflow,
            name: "made-by-automation",
            project_id: project.id
          )
        )
      )
      |> json_response(201)

    assert created["workflow"]["name"] == "made-by-automation"

    updated =
      conn
      |> patch(
        ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
        Jason.encode!(%{name: "renamed-by-automation"})
      )
      |> json_response(200)

    assert updated["workflow"]["name"] == "renamed-by-automation"
  end

  test "lists the credentials linked to a project it is not a member of", %{
    conn: conn,
    project: project
  } do
    credential =
      insert(:credential,
        user: insert(:user),
        project_credentials: [%{project: project}]
      )

    assert ids(
             get(conn, ~p"/api/projects/#{project.id}/credentials"),
             "credentials"
           ) ==
             [credential.id]
  end

  test "is refused what only a person may do, with 403", %{conn: conn} do
    credential = insert(:credential, user: insert(:user))

    for conn <- [
          get(conn, ~p"/api/credentials"),
          post(
            conn,
            ~p"/api/credentials",
            Jason.encode!(%{name: "automation's", body: %{}})
          ),
          delete(conn, ~p"/api/credentials/#{credential.id}")
        ] do
      assert_problem(conn, 403, :forbidden, [])
    end

    assert Repo.reload(credential)
  end

  test "is refused provisioning whatever the body names, holding every grant the token endpoint issues",
       %{project: project} do
    {conn, _account} =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> with_service_account(Lightning.ServiceAccount.AccessToken.scopes())

    fresh = Ecto.UUID.generate()
    projects = Repo.aggregate(Lightning.Projects.Project, :count)

    for body <- [
          %{"name" => "made-by-automation"},
          %{"id" => fresh, "name" => "made-by-automation"},
          %{"id" => "bad"},
          %{"id" => project.id, "name" => "made-by-automation"}
        ] do
      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(403, :forbidden, [])
    end

    assert Repo.aggregate(Lightning.Projects.Project, :count) == projects
    assert Repo.reload!(project).name == "a-project"
  end

  test "is told it needs projects:write to provision without it" do
    {conn, _account} =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> with_service_account(["users:read"])

    projects = Repo.aggregate(Lightning.Projects.Project, :count)

    conn
    |> post(~p"/api/provision", %{"name" => "made-by-automation"})
    |> assert_refused_for_scope("projects:write")

    assert Repo.aggregate(Lightning.Projects.Project, :count) == projects
  end

  defp run_in(project) do
    %{triggers: [trigger], jobs: [job]} =
      workflow = insert(:simple_workflow, project: project)

    %{runs: [run]} =
      work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: build(:dataclip),
        runs: [
          %{
            state: :started,
            dataclip: build(:dataclip),
            starting_trigger: trigger
          }
        ]
      )

    log_line = insert(:log_line, run: run)

    %{
      workflow: workflow,
      job: job,
      work_order: work_order,
      run: run,
      log_line: log_line
    }
  end

  defp ids(conn, key),
    do: conn |> json_response(200) |> Map.fetch!(key) |> Enum.map(& &1["id"])
end
