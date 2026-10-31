defmodule LightningWeb.ProjectMFAEnforcementControllerTest do
  @moduledoc """
  A project's `requires_mfa` must hold on plain routes, not only on the page.

  Every route below sits in the `[:browser, :require_authenticated_user]` scope
  or on the bearer-token `/api` scope, so the `:project_scope` LiveView
  `on_mount` hook that bounces an unenrolled member out of the UI cannot run for
  any of them. They reach the requirement through the authorisation layer
  instead, which is the only place it is written.

  Nearly every assertion here funnels through the same `ProjectUsers`
  `:access_project` check and so fires the same clause —
  `permitted?(_action, %Scope{mfa_satisfied?: false})`. Another route adds no
  MFA coverage on top of that. What a route proves, and the policy unit tests
  cannot, is that it reaches the policy at all rather than authorising off a raw
  query: this file is here to catch a bypass.

  `lib` has around twenty `:access_project` call sites. The routes below are a
  deliberate sample of them — enough to cover each shape that carries project
  data out (nested reads, downloads, the bearer-token API), not an inventory.

  Statuses asserted here are the ones each route already returns when it refuses
  a non-member, since an MFA denial travels the same path. They are not a new
  contract.

  Each refusal is paired with the same request made by an enrolled member of an
  equally MFA-required project, so a fix that refuses everybody fails here
  rather than passing. The one exception, deliberately, is the un-nested
  `/api/jobs`-style list endpoints at the foot of the file: they never resolve a
  project scope, so the requirement does not reach them. That test is a standing
  bypass of exactly the kind described above, written as an assertion rather
  than left for the boundary to be inferred.

  The websocket half lives in `workflow_channel_test.exs` and
  `run_channel_test.exs`.
  """
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  # The member the policy is aimed at: a real member of an MFA-required
  # project who has never set up a second factor.
  defp unenrolled_member(%{conn: conn}) do
    user = insert(:user, mfa_enabled: false)

    project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: user, role: :admin}]
      )

    %{user: user, project: project, conn: log_in_user(conn, user)}
  end

  # A positive control on its own project. Confirms an enrolled member
  # actually gets through, so a policy that refuses everyone can't pass
  # this suite by accident.
  defp enrolled_member(_context) do
    user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

    project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: user, role: :admin}]
      )

    %{
      enrolled_user: user,
      enrolled_project: project,
      enrolled_conn: log_in_user(build_conn(), user)
    }
  end

  defp bearer_conn(user) do
    build_conn()
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header(
      "authorization",
      "Bearer #{Lightning.Accounts.generate_api_token(user)}"
    )
  end

  describe "WorkflowController on an MFA-required project" do
    setup [:unenrolled_member, :enrolled_member]

    setup %{project: project} do
      workflow = insert(:workflow, project: project) |> with_snapshot()
      %{workflow: workflow, job: insert(:job, workflow: workflow)}
    end

    test "refuses to start a manual run", %{
      conn: conn,
      project: project,
      workflow: workflow,
      job: job
    } do
      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          job_id: job.id,
          custom_body: "{\"data\": \"test\"}"
        })

      assert conn.status == 403,
             "an unenrolled member executed a workflow in a project that " <>
               "requires MFA"
    end

    test "refuses to read run steps", %{conn: conn, project: project} do
      %{run: run, job: job, step: step} = run_with_step(project)

      conn =
        get(conn, ~p"/projects/#{project}/runs/#{run}/steps?job_id=#{job.id}")

      assert conn.status == 401

      refute conn.resp_body =~ step.input_dataclip_id,
             "step metadata and a dataclip handle were served to an " <>
               "unenrolled member"
    end

    test "refuses to retry a run", %{conn: conn, project: project} do
      %{run: run, step: step} = run_with_step(project)

      conn =
        post(conn, ~p"/projects/#{project}/runs/#{run}/retry", %{
          step_id: step.id
        })

      assert conn.status == 401,
             "an unenrolled member re-executed a historical run"
    end

    test "still reads run steps for a member who has enrolled", %{
      enrolled_conn: conn,
      enrolled_project: project
    } do
      %{run: run, job: job, step: step} = run_with_step(project)

      conn =
        get(conn, ~p"/projects/#{project}/runs/#{run}/steps?job_id=#{job.id}")

      assert conn.status == 200
      assert conn.resp_body =~ step.input_dataclip_id
    end
  end

  describe "bulk-download routes on an MFA-required project" do
    setup [:unenrolled_member, :enrolled_member]

    test "refuses the raw dataclip body", %{conn: conn, project: project} do
      dataclip =
        insert(:dataclip, project: project, body: %{"patient" => "record"})

      conn = get(conn, ~p"/dataclip/body/#{dataclip.id}")

      assert conn.status == 403

      refute conn.resp_body =~ "patient",
             "the raw dataclip body was served to an unenrolled member"
    end

    test "refuses the project yaml export", %{conn: conn, project: project} do
      conn = get(conn, ~p"/download/yaml?#{%{id: project.id}}")

      assert conn.status == 401,
             "the whole project definition was exported to an unenrolled member"
    end

    test "refuses the work-order export archive", %{
      conn: conn,
      project: project,
      user: user
    } do
      project_file = stored_export(project, user)

      conn = get(conn, ~p"/project_files/#{project_file.id}/download")

      assert conn.status == 403

      refute conn.resp_body =~ "the-export-archive",
             "the export archive was served to an unenrolled member"
    end

    test "still serve all three to a member who has enrolled", %{
      enrolled_conn: conn,
      enrolled_project: project,
      enrolled_user: user
    } do
      dataclip =
        insert(:dataclip, project: project, body: %{"patient" => "record"})

      assert get(conn, ~p"/dataclip/body/#{dataclip.id}").status == 200
      assert get(conn, ~p"/download/yaml?#{%{id: project.id}}").status == 200

      project_file = stored_export(project, user)

      assert get(conn, ~p"/project_files/#{project_file.id}/download").status ==
               200
    end
  end

  describe "collection reads on an MFA-required project" do
    setup [:unenrolled_member, :enrolled_member]

    setup %{project: project, enrolled_project: enrolled_project} do
      %{
        collection: insert(:collection, project: project),
        enrolled_collection: insert(:collection, project: enrolled_project)
      }
    end

    # `:access_collection` is the read half of `Policies.Collections`, and the
    # only half that delegates to `:access_project`. The write actions go
    # through `Scope.role_in?/3` instead and are covered by the scope unit
    # tests, so this is the clause those do not reach.
    test "are refused for a member who has not enrolled", %{
      conn: conn,
      user: user,
      project: project,
      collection: collection
    } do
      api_conn = bearer_conn(user)

      assert get(api_conn, ~p"/collections/#{collection.name}").status == 401,
             "an unenrolled member streamed a collection"

      assert get(api_conn, ~p"/collections/#{collection.name}/a-key").status ==
               401

      assert get(
               conn,
               ~p"/download/collections/#{project.id}/#{collection.name}"
             ).status == 401
    end

    test "are still served to a member who has enrolled", %{
      enrolled_conn: conn,
      enrolled_user: user,
      enrolled_project: project,
      enrolled_collection: collection
    } do
      api_conn = bearer_conn(user)

      assert get(api_conn, ~p"/collections/#{collection.name}").status == 200

      assert get(api_conn, ~p"/collections/#{collection.name}/a-key").status ==
               204

      assert get(
               conn,
               ~p"/download/collections/#{project.id}/#{collection.name}"
             ).status == 200
    end
  end

  describe "the bearer-token API on an MFA-required project" do
    # Decision: `requires_mfa` binds API tokens as well as browser sessions.
    # An unenrolled member's token is refused the same as their session,
    # not exempted.
    setup %{conn: conn} do
      user = insert(:user, mfa_enabled: false)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      %{conn: conn, user: user, project: project}
    end

    setup :enrolled_member

    test "refuses every project-nested resource", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project) |> with_snapshot()

      for {path, refusals} <- [
            {~p"/api/projects/#{project.id}", [401, 403]},
            {~p"/api/projects/#{project.id}/workflows", [401, 403]},
            {~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
             [401, 403]},
            {~p"/api/projects/#{project.id}/credentials", [401, 403]},
            {~p"/api/projects/#{project.id}/work_orders", [401, 403]},
            {~p"/api/projects/#{project.id}/jobs", [401]},
            {~p"/api/projects/#{project.id}/runs", [401]},
            {~p"/api/provision/#{project.id}", [401, 403]},
            {~p"/api/provision/yaml?#{%{id: project.id}}", [401, 403]}
          ] do
        status = get(conn, path).status

        assert status in refusals,
               "#{path} answered #{status} to an unenrolled member, not " <>
                 "#{inspect(refusals)}"
      end
    end

    test "still serves every one of them to a member who has enrolled", %{
      enrolled_user: user,
      enrolled_project: project
    } do
      conn = bearer_conn(user)
      workflow = insert(:workflow, project: project) |> with_snapshot()

      for path <- [
            ~p"/api/projects/#{project.id}",
            ~p"/api/projects/#{project.id}/workflows",
            ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
            ~p"/api/projects/#{project.id}/credentials",
            ~p"/api/projects/#{project.id}/work_orders",
            ~p"/api/projects/#{project.id}/jobs",
            ~p"/api/projects/#{project.id}/runs",
            ~p"/api/provision/#{project.id}",
            ~p"/api/provision/yaml?#{%{id: project.id}}"
          ] do
        assert get(conn, path).status == 200,
               "#{path} was refused to an enrolled member"
      end
    end

    # The boundary of this change, pinned rather than described. The un-nested
    # list endpoints do not resolve a project scope at all — they authorise
    # against a raw `Ecto.assoc(user, :projects)` subquery — so nothing above
    # reaches them. The same subquery is why a project scheduled for deletion
    # keeps being listed; both are fixed together in the follow-up, and
    # these assertions are meant to be inverted by it.
    test "does not yet filter the un-nested list endpoints", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project) |> with_snapshot()
      job = insert(:job, workflow: workflow)

      assert conn |> get(~p"/api/jobs") |> Map.get(:resp_body) =~ job.id

      for path <- [
            ~p"/api/runs",
            ~p"/api/workflows",
            ~p"/api/work_orders",
            ~p"/api/log_lines"
          ] do
        assert get(conn, path).status == 200
      end
    end
  end

  # A run that has actually executed a step, so the endpoints under test reach
  # their success path today rather than 404-ing on a missing step — otherwise
  # these would pass after the fix for the wrong reason.
  defp run_with_step(project) do
    workflow = insert(:workflow, project: project) |> with_snapshot()
    job = insert(:job, workflow: workflow)
    dataclip = insert(:dataclip, project: project)
    work_order = insert(:workorder, workflow: workflow)

    run =
      insert(:run,
        work_order: work_order,
        dataclip: dataclip,
        starting_job: job
      )

    step = insert(:step, job: job, input_dataclip: dataclip, runs: [run])

    %{run: run, job: job, step: step}
  end

  # A completed export with a real file behind it, so the download route
  # reaches its success path rather than erroring on a missing object.
  defp stored_export(project, user) do
    source = Path.join(System.tmp_dir!(), "export-#{Ecto.UUID.generate()}")
    File.write!(source, "the-export-archive")
    on_exit(fn -> File.rm(source) end)

    {:ok, path} =
      Lightning.Storage.store(source, "exports/#{Ecto.UUID.generate()}.zip")

    insert(:project_file,
      project: project,
      created_by: user,
      path: path,
      status: :completed
    )
  end
end
