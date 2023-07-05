defmodule LightningWeb.WorkflowLive.IndexTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "index" do
    test "renders a list of workflows", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert view
             |> element("#workflows-#{project.id}", "No workflows yet")
    end

    test "lists all workflows for a project", %{
      conn: conn,
      project: project
    } do
      workflow_one = insert(:workflow, project: project, name: "One")
      workflow_two = insert(:workflow, project: project, name: "Two")

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w")

      assert html =~ "Create new workflow"

      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/w/#{workflow_one.id}",
               "One"
             )

      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/w/#{workflow_two.id}",
               "Two"
             )
    end

    test "users can delete a workflow"
    test "users with viewer role cannot delete a workflow"
  end

  def has_link?(view, path, text_filter \\ nil) do
    view
    |> element("a[href='#{path}']", text_filter)
  end
end
