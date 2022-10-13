defmodule LightningWeb.JobLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.CredentialsFixtures
  import SweetXml

  alias Lightning.Jobs

  @create_attrs %{
    body: "some body",
    enabled: true,
    name: "some name",
    trigger: %{type: "cron"},
    adaptor_name: "@openfn/language-common",
    adaptor: "@openfn/language-common@latest"
  }
  @update_attrs %{
    body: "some updated body",
    enabled: false,
    name: "some updated name",
    adaptor_name: "@openfn/language-common",
    adaptor: "@openfn/language-common@latest"
  }
  @invalid_attrs %{body: nil, enabled: false, name: nil}

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    job = job_fixture(project_id: project.id)
    %{job: job}
  end

  describe "Index" do
    test "lists all jobs", %{conn: conn, job: job} do
      other_job = job_fixture(name: "other job")

      {:ok, view, html} =
        live(conn, Routes.project_job_index_path(conn, :index, job.project_id))

      assert html =~ "Jobs"

      table = view |> element("section#inner_content") |> render()
      assert table =~ "job-#{job.id}"
      refute table =~ "job-#{other_job.id}"
    end

    test "saves new job", %{conn: conn, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, project.id))

      {:ok, edit_live, _html} =
        index_live
        |> element("a", "New Job")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_job_edit_path(conn, :new, project.id)
        )

      assert edit_live
             |> form("#job-form", job: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      # Set the adaptor name to populate the version dropdown
      assert edit_live
             |> form("#job-form", job: %{adaptor_name: "@openfn/language-common"})
             |> render_change()

      assert edit_live
             |> element("#adaptorVersionField")
             |> render()
             |> parse()
             |> xpath(~x"option/text()"l) == [
               'latest',
               '2.14.0',
               '1.10.3',
               '1.2.22',
               '1.2.14',
               '1.2.3',
               '1.1.12',
               '1.1.0'
             ]

      {:ok, _, html} =
        edit_live
        |> form("#job-form", job: @create_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.project_job_index_path(conn, :index, project.id)
        )

      assert html =~ "Job created successfully"
      assert html =~ "some body"
    end

    test "deletes job in listing", %{conn: conn, job: job} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, job.project_id))

      assert index_live
             |> element("#job-#{job.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#job-#{job.id}")
    end
  end

  describe "Edit" do
    test "updates job in listing", %{conn: conn, job: job} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, job.project_id))

      {:ok, form_live, _} =
        index_live
        |> element("#job-#{job.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_job_edit_path(conn, :edit, job.project_id, job)
        )

      assert form_live
             |> form("#job-form", job: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        form_live
        |> form("#job-form", job: @update_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.project_job_index_path(conn, :index, job.project_id)
        )

      assert html =~ "Job updated successfully"
      assert html =~ "some updated body"
    end

    test "a job created in project B does not appear in the liveview dropdown list for an upstream job when editing a job in project A",
         %{
           conn: conn,
           job: job
         } do
      job_1 = job_fixture()

      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, job.project_id))

      {:ok, form_live, _} =
        index_live
        |> element("#job-#{job.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_job_edit_path(
            conn,
            :edit,
            job.project_id,
            job
          )
        )

      assert form_live
             |> form("#job-form", job: %{trigger: %{type: "on_job_success"}})
             |> render_change()

      displayed_jobs =
        form_live
        |> element("#upstreamJob")
        |> render()
        |> parse()
        |> xpath(~x"option/text()"l)

      assert Enum.member?(displayed_jobs, Jobs.get_job!(job_1.id).name)
             |> Kernel.not()
    end

    test "a job in project A does appear in the 'upstream job' dropdown list for another job in project A",
         %{
           conn: conn,
           job: job
         } do
      job_1 = job_fixture(project_id: job.project_id)

      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, job.project_id))

      {:ok, form_live, _} =
        index_live
        |> element("#job-#{job.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_job_edit_path(
            conn,
            :edit,
            job.project_id,
            job
          )
        )

      assert form_live
             |> form("#job-form", job: %{trigger: %{type: "on_job_success"}})
             |> render_change()

      displayed_jobs =
        form_live
        |> element("#upstreamJob")
        |> render()
        |> parse()
        |> xpath(~x"option/text()"l)

      assert displayed_jobs
             |> Enum.map(fn x -> "#{x}" end)
             |> Enum.member?(Jobs.get_job!(job_1.id).name)
    end

    test "if project A has 6 jobs, the dropdown list displays 5 jobs (all existing jobs minus the one that the user is currently on)",
         %{
           conn: conn,
           project: project,
           job: job
         } do
      # We are adding 5 more jobs to the current project. It will now have 6 jobs (a job is already assigned to it in the setup of this test)
      n_jobs = 5

      new_jobs =
        for _ <- 1..n_jobs,
            do: job_fixture(name: "some other name", project_id: project.id)

      assert Jobs.jobs_for_project(project)
             |> Enum.count() == n_jobs + 1

      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, project.id))

      {:ok, form_live, _} =
        index_live
        |> element("#job-#{job.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_job_edit_path(
            conn,
            :edit,
            job.project_id,
            job
          )
        )

      assert form_live
             |> form("#job-form", job: %{trigger: %{type: "on_job_success"}})
             |> render_change()

      displayed_jobs =
        form_live
        |> element("#upstreamJob")
        |> render()
        |> parse()
        |> xpath(~x"option/text()"l)

      displayed_jobs =
        displayed_jobs |> Enum.map(fn job_name -> "#{job_name}" end)

      assert displayed_jobs |> Enum.count() == n_jobs
      assert displayed_jobs == Enum.map(new_jobs, fn job -> job.name end)
      assert Enum.member?(displayed_jobs, job.name) |> Kernel.not()
    end
  end

  describe "Access Jobs Page" do
    test "a user can't access the jobs page when they are not members of that project",
         %{conn: conn} do
      job = job_fixture(project_id: project_fixture().id)

      assert {:error, {:redirect, %{flash: %{"nav" => :no_access}, to: "/"}}} ==
               live(
                 conn,
                 Routes.project_job_index_path(conn, :index, job.project_id)
               )
    end
  end

  describe "FormComponent.coerce_params_for_adaptor_list/1" do
    test "when adaptor_name is present it sets the adaptor to @latest" do
      assert LightningWeb.JobLive.FormComponent.coerce_params_for_adaptor_list(%{
               "adaptor" => "",
               "adaptor_name" => "@openfn/language-common"
             }) == %{
               "adaptor" => "@openfn/language-common@latest",
               "adaptor_name" => "@openfn/language-common"
             }
    end

    test "when adaptor_name is present and adaptor is the same module" do
      assert LightningWeb.JobLive.FormComponent.coerce_params_for_adaptor_list(%{
               "adaptor" => "@openfn/language-http@1.2.3",
               "adaptor_name" => "@openfn/language-http"
             }) == %{
               "adaptor" => "@openfn/language-http@1.2.3",
               "adaptor_name" => "@openfn/language-http"
             }
    end

    test "when adaptor_name is present but adaptor is a different module" do
      assert LightningWeb.JobLive.FormComponent.coerce_params_for_adaptor_list(%{
               "adaptor" => "@openfn/language-http@1.2.3",
               "adaptor_name" => "@openfn/language-common"
             }) == %{
               "adaptor" => "@openfn/language-common@latest",
               "adaptor_name" => "@openfn/language-common"
             }
    end

    test "when adaptor_name is not present but adaptor is" do
      assert LightningWeb.JobLive.FormComponent.coerce_params_for_adaptor_list(%{
               "adaptor" => "@openfn/language-http@1.2.3",
               "adaptor_name" => ""
             }) == %{
               "adaptor" => "",
               "adaptor_name" => ""
             }
    end

    test "when neither is present" do
      assert LightningWeb.JobLive.FormComponent.coerce_params_for_adaptor_list(%{
               "adaptor" => "",
               "adaptor_name" => ""
             }) == %{
               "adaptor" => "",
               "adaptor_name" => ""
             }
    end
  end
end
