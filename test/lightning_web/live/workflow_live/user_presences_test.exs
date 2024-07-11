defmodule LightningWeb.WorkflowLive.UserPresencesTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.WorkflowLive.Helpers
  import Lightning.Factories

  describe "When only one visitor, no presence is detected" do
    test "in canvas", %{conn: conn} do
      amy =
        insert(:user,
          email: "amy@openfn.org",
          first_name: "Amy",
          last_name: "Ly"
        )

      project =
        insert(:project,
          project_users: [
            %{user: amy, role: :owner}
          ]
        )

      %{workflow: workflow} = create_workflow(%{project: project})

      amy_session = log_in_user(conn, amy)

      {:ok, amy_view, _html} =
        live(
          amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      # Neither banner nor online users components are rendered in Canvas
      refute amy_view |> has_element?("#canvas-online-users-#{amy.id}")
      refute amy_view |> has_element?("#canvas-banner")

      # We do not render current user in the list of online users
      refute render(amy_view) =~ amy.first_name
    end

    test "in inspector", %{conn: conn} do
      amy =
        insert(:user,
          email: "amy@openfn.org",
          first_name: "Amy",
          last_name: "Ly"
        )

      project =
        insert(:project,
          project_users: [
            %{user: amy, role: :owner}
          ]
        )

      %{workflow: %{jobs: [job | _]} = workflow} =
        create_workflow(%{project: project})

      amy_session = log_in_user(conn, amy)

      {:ok, amy_view, _html} =
        live(
          amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job.id, m: "expand"]}"
        )

      # Neither banner nor online users components are rendered in Canvas
      refute amy_view |> has_element?("#inspector-online-users-#{amy.id}")
      refute amy_view |> has_element?("#inspector-banner")

      # We do not render current user in the list of online users
      refute render(amy_view) =~ amy.first_name
    end
  end

  describe "When workflow has many visitors, presences is detected and edit is disabled" do
    test "in canvas", %{conn: conn} do
      amy =
        insert(:user,
          email: "amy@openfn.org",
          first_name: "Amy",
          last_name: "Ly"
        )

      ana =
        insert(:user,
          email: "ana@openfn.org",
          first_name: "Ana",
          last_name: "Ba"
        )

      aly =
        insert(:user,
          email: "aly@openfn.org",
          first_name: "Aly",
          last_name: "Sy"
        )

      project =
        insert(:project,
          project_users: [
            %{user: amy, role: :owner},
            %{user: ana, role: :admin},
            %{user: aly, role: :editor}
          ]
        )

      %{workflow: workflow} = create_workflow(%{project: project})

      amy_session = log_in_user(conn, amy)
      ana_session = log_in_user(conn, ana)
      aly_session = log_in_user(conn, aly)

      {:ok, amy_view, _html} =
        live(
          amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      refute amy_view |> has_element?("#canvas-online-users-#{amy.id}")
      refute amy_view |> has_element?("#canvas-banner")

      refute render(amy_view) =~ amy.first_name

      refute render(amy_view) =~ ana.first_name
      refute render(amy_view) =~ aly.first_name

      # Ana joins
      {:ok, ana_view, _html} =
        live(
          ana_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      refute amy_view |> has_element?("#canvas-online-users-#{amy.id}")
      assert amy_view |> has_element?("#canvas-online-users-#{ana.id}")
      refute amy_view |> has_element?("#canvas-banner-#{amy.id}")

      wait_for_canvas_disabled_state(ana_view, false)

      refute ana_view |> has_element?("#canvas-online-users-#{ana.id}")
      assert ana_view |> has_element?("#canvas-online-users-#{amy.id}")
      assert ana_view |> has_element?("#canvas-banner-#{ana.id}")

      assert ana_view |> element("#canvas-banner-#{ana.id}") |> render() =~
               "Amy Ly is currently active and you can&#39;t edit this workflow until they close the editor and canvas."

      refute render(amy_view) =~ amy.first_name
      assert render(amy_view) =~ ana.first_name

      refute render(ana_view) =~ ana.first_name
      assert render(ana_view) =~ amy.first_name

      # Aly joins
      {:ok, aly_view, _html} =
        live(
          aly_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      refute amy_view |> has_element?("#canvas-online-users-#{amy.id}")
      assert amy_view |> has_element?("#canvas-online-users-#{ana.id}")
      assert amy_view |> has_element?("#canvas-online-users-#{aly.id}")
      refute amy_view |> has_element?("#canvas-banner-#{amy.id}")

      refute ana_view |> has_element?("#canvas-online-users-#{ana.id}")
      assert ana_view |> has_element?("#canvas-online-users-#{amy.id}")
      assert ana_view |> has_element?("#canvas-online-users-#{aly.id}")
      assert ana_view |> has_element?("#canvas-banner-#{ana.id}")

      assert ana_view |> element("#canvas-banner-#{ana.id}") |> render() =~
               "Amy Ly is currently active and you can&#39;t edit this workflow until they close the editor and canvas."

      wait_for_canvas_disabled_state(aly_view, false)

      refute aly_view |> has_element?("#canvas-online-users-#{aly.id}")
      assert aly_view |> has_element?("#canvas-online-users-#{amy.id}")
      assert aly_view |> has_element?("#canvas-online-users-#{ana.id}")
      assert aly_view |> has_element?("#canvas-banner-#{aly.id}")

      assert aly_view |> element("#canvas-banner-#{aly.id}") |> render() =~
               "Amy Ly is currently active and you can&#39;t edit this workflow until they close the editor and canvas."

      refute render(amy_view) =~ amy.first_name
      assert render(amy_view) =~ ana.first_name
      assert render(amy_view) =~ aly.first_name

      refute render(ana_view) =~ ana.first_name
      assert render(ana_view) =~ amy.first_name
      assert render(ana_view) =~ aly.first_name

      refute render(aly_view) =~ aly.first_name
      assert render(aly_view) =~ amy.first_name
      assert render(aly_view) =~ ana.first_name

      last_job = workflow.jobs |> List.last()
      last_edge = workflow.edges |> List.last()

      assert force_event(ana_view, :save) =~
               "Cannot save in view-only mode"

      ana_view
      |> select_node(last_job, workflow.lock_version)

      assert force_event(ana_view, :delete_node, last_job) =~
               "Cannot delete a step in view-only mode"

      ana_view
      |> select_node(last_edge, workflow.lock_version)

      assert force_event(ana_view, :delete_edge, last_edge) =~
               "Cannot delete an edge in view-only mode"

      assert force_event(ana_view, :manual_run_submit, %{}) =~
               "Cannot run in view-only mode"

      assert force_event(ana_view, :rerun, nil, nil) =~
               "Cannot rerun in view-only mode"
    end

    test "in inspector", %{conn: conn} do
      amy =
        insert(:user,
          email: "amy@openfn.org",
          first_name: "Amy",
          last_name: "Ly"
        )

      ana =
        insert(:user,
          email: "ana@openfn.org",
          first_name: "Ana",
          last_name: "Ba"
        )

      aly =
        insert(:user,
          email: "aly@openfn.org",
          first_name: "Aly",
          last_name: "Sy"
        )

      project =
        insert(:project,
          project_users: [
            %{user: amy, role: :owner},
            %{user: ana, role: :admin},
            %{user: aly, role: :editor}
          ]
        )

      %{workflow: %{jobs: [job | _]} = workflow} =
        create_workflow(%{project: project})

      amy_session = log_in_user(conn, amy)
      ana_session = log_in_user(conn, ana)
      aly_session = log_in_user(conn, aly)

      {:ok, amy_view, _html} =
        live(
          amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job.id, m: "expand"]}"
        )

      wait_for_canvas_disabled_state(amy_view, false)

      refute amy_view |> has_element?("#inspector-online-users-#{amy.id}")
      refute amy_view |> has_element?("#inspector-banner")

      refute render(amy_view) =~ amy.first_name

      refute render(amy_view) =~ ana.first_name
      refute render(amy_view) =~ aly.first_name

      # Ana joins
      {:ok, ana_view, _html} =
        live(
          ana_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job.id, m: "expand"]}"
        )

      wait_for_canvas_disabled_state(ana_view, true)

      refute amy_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert amy_view |> has_element?("#inspector-online-users-#{ana.id}")
      refute amy_view |> has_element?("#inspector-banner-#{amy.id}")

      refute ana_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert ana_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert ana_view |> has_element?("#inspector-banner-#{ana.id}")

      assert ana_view |> element("#canvas-banner-#{ana.id}") |> render() =~
               "Amy Ly is currently active and you can&#39;t edit this workflow until they close the editor and canvas."

      refute render(amy_view) =~ amy.first_name
      assert render(amy_view) =~ ana.first_name

      refute render(ana_view) =~ ana.first_name
      assert render(ana_view) =~ amy.first_name

      # Aly joins
      {:ok, aly_view, _html} =
        live(
          aly_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job.id, m: "expand"]}"
        )

      wait_for_canvas_disabled_state(aly_view, false)

      refute amy_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert amy_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert amy_view |> has_element?("#inspector-online-users-#{aly.id}")
      refute amy_view |> has_element?("#inspector-banner-#{amy.id}")

      refute ana_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert ana_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert ana_view |> has_element?("#inspector-online-users-#{aly.id}")
      assert ana_view |> has_element?("#inspector-banner-#{ana.id}")

      assert ana_view |> element("#canvas-banner-#{ana.id}") |> render() =~
               "Amy Ly is currently active and you can&#39;t edit this workflow until they close the editor and canvas."

      refute aly_view |> has_element?("#inspector-online-users-#{aly.id}")
      assert aly_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert aly_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert aly_view |> has_element?("#inspector-banner-#{aly.id}")

      assert aly_view |> element("#canvas-banner-#{aly.id}") |> render() =~
               "Amy Ly is currently active and you can&#39;t edit this workflow until they close the editor and canvas."

      refute render(amy_view) =~ amy.first_name
      assert render(amy_view) =~ ana.first_name
      assert render(amy_view) =~ aly.first_name

      refute render(ana_view) =~ ana.first_name
      assert render(ana_view) =~ amy.first_name
      assert render(ana_view) =~ aly.first_name

      refute render(aly_view) =~ aly.first_name
      assert render(aly_view) =~ amy.first_name
      assert render(aly_view) =~ ana.first_name
    end
  end

  describe "When workflow has many visits from same user, multiple sessions are detected and edit is disabled" do
    test "in canvas", %{conn: conn} do
      amy =
        insert(:user,
          email: "amy@openfn.org",
          first_name: "Amy",
          last_name: "Ly"
        )

      project =
        insert(:project,
          project_users: [
            %{user: amy, role: :owner}
          ]
        )

      %{workflow: workflow} = create_workflow(%{project: project})

      amy_session = log_in_user(conn, amy)
      another_amy_session = log_in_user(conn, amy)

      {:ok, amy_view, _html} =
        live(
          amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      # Amy joins in another session
      {:ok, another_amy_view, _html} =
        live(
          another_amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      wait_for_canvas_disabled_state(amy_view, false)
      assert amy_view |> has_element?("#canvas-banner-#{amy.id}")

      wait_for_canvas_disabled_state(another_amy_view, false)
      assert another_amy_view |> has_element?("#canvas-banner-#{amy.id}")

      assert amy_view |> element("#canvas-banner-#{amy.id}") |> render() =~
               "You have this workflow open in 2 tabs and can&#39;t edit until you close the other."

      assert another_amy_view |> element("#canvas-banner-#{amy.id}") |> render() =~
               "You have this workflow open in 2 tabs and can&#39;t edit until you close the other."
    end

    test "in inspector", %{conn: conn} do
      amy =
        insert(:user,
          email: "amy@openfn.org",
          first_name: "Amy",
          last_name: "Ly"
        )

      project =
        insert(:project,
          project_users: [
            %{user: amy, role: :owner}
          ]
        )

      %{workflow: %{jobs: [job | _]} = workflow} =
        create_workflow(%{project: project})

      amy_session = log_in_user(conn, amy)
      another_amy_session = log_in_user(conn, amy)

      {:ok, amy_view, _html} =
        live(
          amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job.id, m: "expand"]}"
        )

      # Amy joins in another session
      {:ok, another_amy_view, _html} =
        live(
          another_amy_session,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job.id, m: "expand"]}"
        )

      wait_for_canvas_disabled_state(amy_view, false)
      assert amy_view |> has_element?("#inspector-banner-#{amy.id}")

      wait_for_canvas_disabled_state(another_amy_view, false)
      assert another_amy_view |> has_element?("#inspector-banner-#{amy.id}")

      assert amy_view |> element("#inspector-banner-#{amy.id}") |> render() =~
               "You have this workflow open in 2 tabs and can&#39;t edit until you close the other."

      assert another_amy_view
             |> element("#inspector-banner-#{amy.id}")
             |> render() =~
               "You have this workflow open in 2 tabs and can&#39;t edit until you close the other."
    end
  end

  # HACK: This is a workaround to wait for presence to be syncronized.
  # This is used above to wait for other users to have their presence
  # updated, so we can assert that they can see other users.
  defp wait_for_canvas_disabled_state(view, state) do
    {ref, _, _} = view.proxy

    assert_receive({^ref, {:push_event, "set-disabled", %{disabled: ^state}}})
  end
end
