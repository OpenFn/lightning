defmodule LightningWeb.JobLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures

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

  defp create_job(_) do
    job = job_fixture()
    %{job: job}
  end

  describe "Index" do
    setup [:create_job]

    test "lists all jobs", %{conn: conn, job: job} do
      {:ok, _index_live, html} = live(conn, Routes.job_index_path(conn, :index))

      assert html =~ "Listing Jobs"
      assert html =~ job.body
    end

    test "saves new job", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.job_index_path(conn, :index))

      assert index_live |> element("a", "New Job") |> render_click() =~
               "New Job"

      assert_patch(index_live, Routes.job_index_path(conn, :new))

      assert index_live
             |> form("#job-form", job: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      # Set the adaptor name to populate the version dropdown
      assert index_live
             |> form("#job-form", job: %{adaptor_name: "@openfn/language-common"})
             |> render_change()

      {:ok, _, html} =
        index_live
        |> form("#job-form", job: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.job_index_path(conn, :index))

      assert html =~ "Job created successfully"
      assert html =~ "some body"
    end

    test "deletes job in listing", %{conn: conn, job: job} do
      {:ok, index_live, _html} = live(conn, Routes.job_index_path(conn, :index))

      assert index_live |> element("#job-#{job.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#job-#{job.id}")
    end
  end

  describe "Edit" do
    setup [:create_job]

    test "updates job in listing", %{conn: conn, job: job} do
      {:ok, index_live, _html} = live(conn, Routes.job_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#job-#{job.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.job_edit_path(conn, :edit, job))

      assert form_live
             |> form("#job-form", job: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        form_live
        |> form("#job-form", job: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.job_index_path(conn, :index))

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

  # describe "Show" do
  #   setup [:create_job]

  #   test "displays job", %{conn: conn, job: job} do
  #     {:ok, _show_live, html} = live(conn, Routes.job_show_path(conn, :show, job))

  #     assert html =~ "Show Job"
  #     assert html =~ job.body
  #   end

  #   test "updates job within modal", %{conn: conn, job: job} do
  #     {:ok, show_live, _html} = live(conn, Routes.job_show_path(conn, :show, job))

  #     assert show_live |> element("a", "Edit") |> render_click() =~
  #              "Edit Job"

  #     assert_patch(show_live, Routes.job_show_path(conn, :edit, job))

  #     assert show_live
  #            |> form("#job-form", job: @invalid_attrs)
  #            |> render_change() =~ "can&#39;t be blank"

  #     {:ok, _, html} =
  #       show_live
  #       |> form("#job-form", job: @update_attrs)
  #       |> render_submit()
  #       |> follow_redirect(conn, Routes.job_show_path(conn, :show, job))

  #     assert html =~ "Job updated successfully"
  #     assert html =~ "some updated body"
  #   end
  # end
end
