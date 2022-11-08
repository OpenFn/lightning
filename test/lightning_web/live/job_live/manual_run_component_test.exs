defmodule LightningWeb.JobLive.ManualRunComponentTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.InvocationFixtures

  alias LightningWeb.RouteHelpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    job = job_fixture(project_id: project.id)
    %{job: job}
  end

  defp enter_dataclip_id(view, value) do
    view
    |> element("input[name='manual_run[dataclip_id]']")
    |> render_change(manual_run: [dataclip_id: value])
  end

  defp run_button(view, disabled \\ '') do
    view
    |> element("button[disabled='#{disabled}']", "Run")
  end

  test "renders", %{conn: conn, job: job, project: project} do
    {:ok, view, _html} =
      live(conn, RouteHelpers.workflow_edit_job_path(project.id, job.id))

    assert view |> enter_dataclip_id("") =~ html_escape("can't be blank")
    assert view |> enter_dataclip_id("abc") =~ "is invalid"

    refute view |> enter_dataclip_id(Ecto.UUID.generate()) =~
             html_escape("is invalid")

    assert view |> run_button() |> render_click() =~
             html_escape("doesn't exist")

    assert view |> run_button('disabled') |> has_element?()

    dataclip = dataclip_fixture()

    refute view |> enter_dataclip_id(dataclip.id) =~
             html_escape("is invalid")

    assert view |> run_button() |> render_click() =~
             "Run enqueued."
  end

  test "doesn't appear on new Job", %{conn: conn, project: project} do
    {:ok, view, _html} =
      live(conn, RouteHelpers.workflow_new_job_path(project.id))

    refute view |> has_element?("input[name='manual_run[dataclip_id]']")
  end
end
