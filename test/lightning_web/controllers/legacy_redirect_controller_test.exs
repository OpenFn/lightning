defmodule LightningWeb.LegacyRedirectControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "legacy editor redirects" do
    test "redirects /w/new/legacy to the collaborative new workflow editor", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, ~p"/projects/#{project.id}/w/new/legacy")

      assert redirected_to(conn) == "/projects/#{project.id}/w/new"
    end

    test "redirects /w/:id/legacy to the collaborative editor", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      conn = get(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/legacy")

      assert redirected_to(conn) ==
               "/projects/#{project.id}/w/#{workflow.id}"
    end

    test "remaps the legacy 'a' (followed run) param to 'run'", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      conn =
        get(conn, "/projects/#{project.id}/w/#{workflow.id}/legacy?a=run-1")

      target = URI.parse(redirected_to(conn))

      assert target.path == "/projects/#{project.id}/w/#{workflow.id}"
      assert URI.decode_query(target.query) == %{"run" => "run-1"}
    end

    test "forwards other legacy params unchanged alongside the 'a' remap", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      conn =
        get(
          conn,
          "/projects/#{project.id}/w/#{workflow.id}/legacy?s=some-job&m=expand&a=run-1"
        )

      target = URI.parse(redirected_to(conn))

      assert target.path == "/projects/#{project.id}/w/#{workflow.id}"

      assert URI.decode_query(target.query) == %{
               "run" => "run-1",
               "s" => "some-job",
               "m" => "expand"
             }
    end
  end
end
