defmodule LightningWeb.WorkflowLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  import Lightning.JobsFixtures

  describe "show" do
    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "renders the workflow diagram", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(conn, Routes.project_workflow_path(conn, :show, project.id))

      assert html =~ project.name

      expected_encoded_project_space =
        Lightning.Workflows.get_workflows_for(project)
        |> Lightning.Workflows.to_project_space()
        |> Jason.encode!()
        |> Base.encode64()

      assert view
             |> element("div#hook-#{project.id}[phx-update=ignore]")
             |> render() =~ expected_encoded_project_space
    end
  end

  describe "edit_job" do
    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "renders the job inspector", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
        )

      assert html =~ project.name

      assert has_element?(view, "#job-#{job.id}")
    end
  end

  describe "edit_workflow" do
    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "renders the workflow inspector", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :edit_workflow,
            project.id,
            job.workflow_id
          )
        )

      assert html =~ project.name

      assert has_element?(view, "#workflow-#{job.workflow_id}")

      assert view
             |> form("#workflow-form", workflow: %{name: "my workflow"})
             |> render_change()

      view |> form("#workflow-form") |> render_submit()

      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      assert view |> encoded_project_space_matches(project)
    end
  end

  describe "new_job" do
    setup %{project: project} do
      %{upstream_job: job_fixture(project_id: project.id)}
    end

    test "renders the workflow inspector", %{
      conn: conn,
      project: project,
      upstream_job: upstream_job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :new_job,
            project.id,
            %{"upstream_id" => upstream_job.id}
          )
        )

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> element(
               ~S{#job-form select#upstreamJob option[selected=selected]}
             )
             |> render() =~ upstream_job.id,
             "Should have the upstream job selected"

      assert view
             |> form("#job-form", job: %{adaptor_name: "@openfn/language-common"})
             |> render_change()

      assert view
             |> form("#job-form",
               job: %{
                 body: "some body",
                 enabled: true,
                 name: "some name",
                 trigger: %{type: "on_job_failure"},
                 adaptor: "@openfn/language-common@latest"
               }
             )
             |> render_submit()

      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      assert view |> encoded_project_space_matches(project)
    end
  end

  defp extract_project_space(html) do
    [_, result] = Regex.run(~r/data-project-space="([[:alnum:]\=]+)"/, html)
    result
  end

  # Pull out the encoded ProjectSpace data from the html, turn it back into a
  # map and compare it to the current value.
  defp encoded_project_space_matches(view, project) do
    view
    |> element("div#hook-#{project.id}[phx-update=ignore]")
    |> render()
    |> extract_project_space()
    |> Base.decode64!()
    |> Jason.decode!() ==
      Lightning.Workflows.get_workflows_for(project)
      |> Lightning.Workflows.to_project_space()
      |> Jason.encode!()
      |> Jason.decode!()
  end
end
