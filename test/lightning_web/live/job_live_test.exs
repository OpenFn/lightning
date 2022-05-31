defmodule LightningWeb.JobLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import SweetXml

  @create_attrs %{
    body: "some body",
    enabled: true,
    name: "some name",
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

      {:ok, _index_live, html} =
        live(conn, Routes.project_job_index_path(conn, :index, job.project_id))

      assert html =~ "Listing Jobs"
      refute html =~ other_job.name
      assert html =~ job.name
      assert html =~ job.body |> Phoenix.HTML.Safe.to_iodata() |> to_string()
    end

    test "saves new job", %{conn: conn, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, project.id))

      assert index_live |> element("a", "New Job") |> render_click() =~
               "New Job"

      assert_patch(
        index_live,
        Routes.project_job_index_path(conn, :new, project.id)
      )

      assert index_live
             |> form("#job-form", job: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      # Set the adaptor name to populate the version dropdown
      assert index_live
             |> form("#job-form", job: %{adaptor_name: "@openfn/language-common"})
             |> render_change()

      assert index_live
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
        index_live
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
  end

  describe "coerce_params_for_adaptor_list/1" do
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

  describe "Show" do
    test "displays job", %{conn: conn, job: job, project: project} do
      {:ok, _show_live, html} =
        live(conn, Routes.project_job_show_path(conn, :show, project, job))

      assert html =~ "Show Job"
      assert html =~ job.name
    end

    test "updates job within modal", %{conn: conn, job: job, project: project} do
      {:ok, show_live, _html} =
        live(conn, Routes.project_job_show_path(conn, :show, project, job))

      {:ok, view, _} =
        show_live
        |> element("a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_job_edit_path(conn, :edit, project, job)
        )

      assert view
             |> form("#job-form", job: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        view
        |> form("#job-form", job: @update_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.project_job_index_path(conn, :index, project)
        )

      assert html =~ "Job updated successfully"
      assert html =~ "some updated body"
    end
  end
end
