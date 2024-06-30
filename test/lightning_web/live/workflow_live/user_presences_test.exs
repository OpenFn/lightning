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

      refute ana_view |> has_element?("#canvas-online-users-#{ana.id}")
      assert ana_view |> has_element?("#canvas-online-users-#{amy.id}")
      assert ana_view |> has_element?("#canvas-banner-#{ana.id}")

      assert ana_view |> element("#canvas-banner-#{ana.id}") |> render() =~
               "This workflow is currently locked for editing because a collaborator (Amy Ly) is currently working on it. You will be able to inspect this workflow and its associated jobs but will not be able to make changes."

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
               "This workflow is currently locked for editing because a collaborator (Amy Ly) is currently working on it. You will be able to inspect this workflow and its associated jobs but will not be able to make changes."

      refute aly_view |> has_element?("#canvas-online-users-#{aly.id}")
      assert aly_view |> has_element?("#canvas-online-users-#{amy.id}")
      assert aly_view |> has_element?("#canvas-online-users-#{ana.id}")
      assert aly_view |> has_element?("#canvas-banner-#{aly.id}")

      assert aly_view |> element("#canvas-banner-#{aly.id}") |> render() =~
               "This workflow is currently locked for editing because a collaborator (Amy Ly) is currently working on it. You will be able to inspect this workflow and its associated jobs but will not be able to make changes."

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

      refute amy_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert amy_view |> has_element?("#inspector-online-users-#{ana.id}")
      refute amy_view |> has_element?("#inspector-banner-#{amy.id}")

      refute ana_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert ana_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert ana_view |> has_element?("#inspector-banner-#{ana.id}")

      assert ana_view |> element("#canvas-banner-#{ana.id}") |> render() =~
               "This workflow is currently locked for editing because a collaborator (Amy Ly) is currently working on it. You will be able to inspect this workflow and its associated jobs but will not be able to make changes."

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

      refute amy_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert amy_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert amy_view |> has_element?("#inspector-online-users-#{aly.id}")
      refute amy_view |> has_element?("#inspector-banner-#{amy.id}")

      refute ana_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert ana_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert ana_view |> has_element?("#inspector-online-users-#{aly.id}")
      assert ana_view |> has_element?("#inspector-banner-#{ana.id}")

      assert ana_view |> element("#canvas-banner-#{ana.id}") |> render() =~
               "This workflow is currently locked for editing because a collaborator (Amy Ly) is currently working on it. You will be able to inspect this workflow and its associated jobs but will not be able to make changes."

      refute aly_view |> has_element?("#inspector-online-users-#{aly.id}")
      assert aly_view |> has_element?("#inspector-online-users-#{amy.id}")
      assert aly_view |> has_element?("#inspector-online-users-#{ana.id}")
      assert aly_view |> has_element?("#inspector-banner-#{aly.id}")

      assert aly_view |> element("#canvas-banner-#{aly.id}") |> render() =~
               "This workflow is currently locked for editing because a collaborator (Amy Ly) is currently working on it. You will be able to inspect this workflow and its associated jobs but will not be able to make changes."

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

      assert amy_view |> has_element?("#canvas-banner-#{amy.id}")
      assert another_amy_view |> has_element?("#canvas-banner-#{amy.id}")

      assert amy_view |> element("#canvas-banner-#{amy.id}") |> render() =~
               "You can&#39;t edit this workflow because you have 2 sessions currently openning it. Please make sure you have only one session opening this workflow to have edit mode enabled."

      assert another_amy_view |> element("#canvas-banner-#{amy.id}") |> render() =~
               "You can&#39;t edit this workflow because you have 2 sessions currently openning it. Please make sure you have only one session opening this workflow to have edit mode enabled."
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

      assert amy_view |> has_element?("#inspector-banner-#{amy.id}")
      assert another_amy_view |> has_element?("#inspector-banner-#{amy.id}")

      assert amy_view |> element("#inspector-banner-#{amy.id}") |> render() =~
               "You can&#39;t edit this workflow because you have 2 sessions currently openning it. Please make sure you have only one session opening this workflow to have edit mode enabled."

      assert another_amy_view
             |> element("#inspector-banner-#{amy.id}")
             |> render() =~
               "You can&#39;t edit this workflow because you have 2 sessions currently openning it. Please make sure you have only one session opening this workflow to have edit mode enabled."
    end
  end
end
