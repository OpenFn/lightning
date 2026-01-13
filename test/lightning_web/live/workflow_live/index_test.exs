defmodule LightningWeb.WorkflowLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  import Lightning.Factories
  import Lightning.WorkflowsFixtures
  import Lightning.WorkflowLive.Helpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :create_workflow
  setup :stub_usage_limiter_ok
  setup :verify_on_exit!

  describe "index" do
    test "renders an empty list of workflows", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert view
             |> element("#workflows-#{project.id}", "No workflows yet")
    end

    test "renders a component when run limit has been reached", %{
      conn: conn,
      project: %{id: project_id}
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :check_limits,
        &Lightning.Extensions.StubUsageLimiter.check_limits/1
      )

      {:ok, _view, html} = live(conn, ~p"/projects/#{project_id}/w")

      assert html =~ "Some banner text"
    end

    test "doesn't render error tooltip when limit is reached; we allow create but block save",
         %{
           conn: conn,
           project: %{id: project_id}
         } do
      Mox.verify_on_exit!()
      error_message = "some funny error message"

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        0,
        fn %{type: :activate_workflow}, %{project_id: ^project_id} ->
          {:error, :too_many_workflows, %{text: error_message}}
        end
      )

      {:ok, _view, html} = live(conn, ~p"/projects/#{project_id}/w")

      refute html =~ error_message
    end

    test "only users with MFA enabled can access workflows for a project with MFA requirement",
         %{
           conn: conn
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = log_in_user(conn, user)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      create_workflow(%{project: project})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/w")

      assert element(view, "#workflows-#{project.id}", "No workflows yet")

      ~w(editor viewer admin)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert {:error, {:redirect, %{to: "/mfa_required"}}} =
                 live(conn, ~p"/projects/#{project}/w")
      end)
    end

    test "shows the Dashboard for a project", %{
      conn: conn,
      project: project,
      workflow: new_workflow
    } do
      workflow1 =
        complex_workflow_with_runs(
          name: "One",
          project: project,
          last_workorder_failed: true
        )

      workflow2 =
        complex_workflow_with_runs(
          name: "Two",
          project: project,
          last_workorder_failed: false
        )

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w")

      # Metrics
      # 10 total workorders
      # 10 total runs (4 pending)
      # 2 successful runs out of 4 completed
      # 2 work orders failed out of 10
      assert Regex.match?(~r/Work Orders.*?<div>\s*10.*\(6 pending\)/s, html)

      pending_and_date_filter =
        Timex.now()
        |> Timex.shift(months: -1)
        |> Date.to_string()
        |> then(fn date ->
          "filters[date_after]=&amp;filters[date_before]=&amp;filters[id]=true&amp;filters[log]=true&amp;filters[pending]=true&amp;filters[running]=true&amp;filters[wo_date_after]=#{date}"
        end)

      assert html
             |> has_history_link_pattern?(
               project,
               pending_and_date_filter,
               "6 pending"
             )

      assert Regex.match?(~r/Runs.*?<div>\s*10.*">\s*\(6 pending\)/s, html)

      assert Regex.match?(
               ~r/Successful Runs.*<div>\s*2.*">\s*\(50.0%\)/s,
               html
             )

      assert Regex.match?(
               ~r/Work Orders in failed state.*<div>\s*2.*">\s*\(20.0%\)/s,
               html
             )

      failed_filter_pattern =
        "filters[cancelled]=true.*filters[crashed]=true.*filters[exception]=true.*filters[failed]=true.*filters[killed]=true.*filters[lost]=true"

      assert html
             |> has_history_link_pattern?(
               project,
               failed_filter_pattern,
               "View all"
             )

      refute html
             |> has_history_link_pattern?(
               project,
               "filters[success]=true"
             )

      # Header
      assert Regex.match?(~r/Workflows.*h3>/s, html)

      assert Regex.match?(
               ~r/<button.*id="new-workflow-button".*Create new workflow.*button>/s,
               html
             )

      assert view
             |> has_element?("tr#workflow-#{workflow1.id} span", "One")

      assert view
             |> has_element?("tr#workflow-#{workflow2.id} span", "Two")

      assert view
             |> has_element?(
               "tr#workflow-#{new_workflow.id} span",
               new_workflow.name
             )

      refute html
             |> has_history_link_pattern?(
               project,
               "filters[workflow_id]=#{new_workflow.id}"
             )

      # Work orders links
      workorders_count = "4"

      # work order date filter without status filter
      date_filter =
        Timex.now()
        |> Timex.shift(months: -1)
        |> Date.to_string()
        |> then(fn date ->
          "filters[date_after]=&amp;filters[date_before]=&amp;filters[id]=true&amp;filters[log]=true&amp;filters[wo_date_after]=#{date}"
        end)

      assert html
             |> has_history_link_pattern?(
               project,
               "filters[workflow_id]=#{workflow1.id}.*#{date_filter}",
               workorders_count
             )

      assert html
             |> has_history_link_pattern?(
               project,
               "filters[workflow_id]=#{workflow2.id}.*#{date_filter}",
               workorders_count
             )

      # Failed runs links
      failed_runs_count = "1"

      assert html
             |> has_history_link_pattern?(
               project,
               "filters[workflow_id]=#{workflow1.id}.*#{failed_filter_pattern}",
               failed_runs_count
             )

      assert html
             |> has_history_link_pattern?(
               project,
               "filters[workflow_id]=#{workflow2.id}.*#{failed_filter_pattern}",
               failed_runs_count
             )

      assert Regex.match?(
               ~r/(8 steps.*#{round(5 / 7 * 100 * 100) / 100}% success)/s,
               html
             )

      # Last workflow with placeholders
      assert Regex.match?(
               ~r{Two.*#{new_workflow.name}.*Nothing last.*0.*N/A.*0.*N/A}s,
               html
             )
    end

    test "enable / disable workflows from dashboard page", %{
      conn: conn,
      project: %{id: project_id} = project
    } do
      cron_trigger = build(:trigger, type: :cron, enabled: false)
      webhook_trigger = build(:trigger, type: :webhook, enabled: false)

      job_1 = build(:job)
      job_2 = build(:job)

      cron_workflow =
        build(:workflow, project: project)
        |> with_job(job_1)
        |> with_trigger(cron_trigger)
        |> with_edge({cron_trigger, job_1})
        |> insert()

      webhook_workflow =
        build(:workflow, project: project)
        |> with_job(job_2)
        |> with_trigger(webhook_trigger)
        |> with_edge({webhook_trigger, job_2})
        |> insert()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      counter = :counters.new(1, [:atomics])

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn %{
                                                                          type:
                                                                            :activate_workflow
                                                                        },
                                                                        %{
                                                                          project_id:
                                                                            ^project_id
                                                                        } ->
        :counters.add(counter, 1, 1)

        case :counters.get(counter, 1) do
          # create workflow button is enabled before the workflow activations but disabled after
          # 1 for limit action of first toggle
          # 1 for push_patch rerender
          # 1 for limit action of second toggle
          n when n <= 3 ->
            :ok

          _error ->
            {:error, :too_many_workflows, %{text: "Error after 2nd activation"}}
        end
      end)

      [cron_workflow, webhook_workflow]
      |> Enum.each(fn workflow ->
        trigger_type =
          workflow.triggers |> List.first() |> Map.get(:type) |> Atom.to_string()

        assert view
               |> has_element?(
                 "#toggle-container-#{workflow.id}[aria-label='This workflow is inactive (manual runs only)']"
               )

        assert view
               |> element("#toggle-control-#{workflow.id}")
               |> render_click() =~
                 "Workflow updated"

        assert view
               |> has_element?(
                 "#toggle-container-#{workflow.id}[aria-label='This workflow is active (#{trigger_type} trigger enabled)']"
               )
      end)

      # Make sure the new workflow button is enabled, even though the toggles are disabled.
      assert view |> has_element?("#new-workflow-button[type=button]")
      refute view |> has_element?("#new-workflow-button[type=button][disabled]")
    end
  end

  describe "creating workflows" do
    @tag role: :viewer
    test "users with viewer role cannot create a workflow", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert has_element?(view, "#new-workflow-button:disabled")

      assert_raise ArgumentError,
                   "cannot click element \"#new-workflow-button\" because it is disabled",
                   fn ->
                     view |> element("#new-workflow-button") |> render_click()
                   end

      # visit page directly
      {:ok, _, html} =
        live(conn, ~p"/projects/#{project.id}/w/new/collaborate")
        |> follow_redirect(conn)

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "users with editor role can create a workflow", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      refute has_element?(view, "#new-workflow-button:disabled")
      assert has_element?(view, "#new-workflow-button")

      # go directly
      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new/collaborate")

      assert html =~ "Describe your workflow"
      assert has_element?(view, "form#search-templates-form")

      select_template(view, "base-webhook-template")

      view |> element("button#create_workflow_btn") |> render_click()

      # the panel disappears
      html = render(view)

      refute html =~ "Describe your workflow"
      refute has_element?(view, "form#search-templates-form")
    end

    test "only users with MFA enabled can create workflows for a project with MFA requirement",
         %{
           conn: conn
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = log_in_user(conn, user)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      create_workflow(%{project: project})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project}/w")

      assert html =~ "Create new workflow"

      ~w(editor admin)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert {:error, {:redirect, %{to: "/mfa_required"}}} =
                 live(conn, ~p"/projects/#{project}/w")
      end)
    end
  end

  describe "deleting workflows" do
    @tag role: :viewer
    test "users with viewer role cannot delete a workflow", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      refute view |> has_delete_workflow_link?(workflow)

      assert view |> render_click("delete_workflow", %{"id" => workflow.id}) =~
               "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "users with editor role can delete a workflow", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert has_workflow_card?(view, workflow)

      assert view |> has_delete_workflow_link?(workflow)

      assert view |> click_delete_workflow(workflow) =~
               "Workflow successfully deleted."

      refute has_workflow_card?(view, workflow)
    end

    @tag role: :editor
    test "audits when a workflow has been marked for deletion", %{
      conn: conn,
      project: project,
      user: %{id: user_id},
      workflow: %{id: workflow_id} = workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      view |> click_delete_workflow(workflow)

      audit = Lightning.Repo.one(Lightning.Auditing.Audit)

      assert %{
               event: "marked_for_deletion",
               item_id: ^workflow_id,
               actor_id: ^user_id
             } = audit
    end
  end

  describe "search workflows" do
    test "filters workflows by search term", %{conn: conn, project: project} do
      w1 = insert(:workflow, project: project, name: "API Gateway")
      w2 = insert(:workflow, project: project, name: "Background Jobs")
      _w3 = insert(:workflow, project: project, name: "REST API")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w?q=api")

      assert has_workflow_card?(view, w1)
      refute has_workflow_card?(view, w2)

      assert view |> has_element?("input[name='search_workflows'][value='api']")
    end

    test "clears search term", %{conn: conn, project: project} do
      insert(:workflow, project: project, name: "API Gateway")
      insert(:workflow, project: project, name: "Background Jobs")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w?q=api")

      assert view
             |> element("#clear_search_button")
             |> render_click() =~ "Background Jobs"

      assert_patch(view, ~p"/projects/#{project.id}/w?sort=name&dir=asc")
    end

    test "updates search in real-time", %{conn: conn, project: project} do
      insert(:workflow, project: project, name: "API Gateway")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert view
             |> element("input[name='search_workflows']")
             |> render_keyup(%{value: "api"}) =~ "API Gateway"
    end

    test "shows appropriate empty state message with search term", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w?q=nonexistent")

      assert html =~
               "No workflows found matching &quot;nonexistent&quot;. Try a different search term or"

      assert html =~
               "<a href=\"/projects/#{project.id}/w/new\" data-phx-link=\"redirect\" data-phx-link-state=\"push\" class=\"link\">\n              create a new one"
    end
  end

  describe "sorting workflows" do
    test "sorts workflows by all available fields", %{
      conn: conn,
      project: project
    } do
      w1 = insert(:workflow, project: project, name: "A Workflow")
      w2 = insert(:workflow, project: project, name: "B Workflow")

      trigger1 =
        insert(:trigger,
          workflow: w1,
          type: :webhook,
          enabled: true,
          custom_path: "path1"
        )

      trigger2 =
        insert(:trigger,
          workflow: w2,
          type: :webhook,
          enabled: false,
          custom_path: "path2"
        )

      _trigger1b =
        insert(:trigger,
          workflow: w1,
          type: :cron,
          enabled: true,
          cron_expression: "* * * * *"
        )

      dataclip = insert(:dataclip)

      insert(:workorder,
        workflow: w1,
        trigger: trigger1,
        dataclip: dataclip,
        state: :failed,
        updated_at: DateTime.utc_now()
      )

      insert(:workorder,
        workflow: w1,
        trigger: trigger1,
        dataclip: dataclip,
        state: :failed,
        updated_at: DateTime.utc_now() |> DateTime.add(-1, :hour)
      )

      insert(:workorder,
        workflow: w1,
        trigger: trigger1,
        dataclip: dataclip,
        state: :success,
        updated_at: DateTime.utc_now() |> DateTime.add(-2, :hour)
      )

      insert(:workorder,
        workflow: w2,
        trigger: trigger2,
        dataclip: dataclip,
        state: :failed,
        updated_at: DateTime.utc_now() |> DateTime.add(-3, :hour)
      )

      insert(:workorder,
        workflow: w2,
        trigger: trigger2,
        dataclip: dataclip,
        state: :success,
        updated_at: DateTime.utc_now() |> DateTime.add(-4, :hour)
      )

      w1 =
        Lightning.Repo.get!(Lightning.Workflows.Workflow, w1.id)
        |> Lightning.Repo.preload(:triggers)

      w2 =
        Lightning.Repo.get!(Lightning.Workflows.Workflow, w2.id)
        |> Lightning.Repo.preload(:triggers)

      test_cases = [
        {"name", "asc", [w1, w2]},
        {"name", "desc", [w2, w1]},
        {"workorders_count", "desc", [w1, w2]},
        {"workorders_count", "asc", [w2, w1]},
        {"failed_workorders_count", "desc", [w1, w2]},
        {"failed_workorders_count", "asc", [w2, w1]},
        {"last_workorder_updated_at", "desc", [w1, w2]},
        {"last_workorder_updated_at", "asc", [w2, w1]},
        {"enabled", "desc", [w1, w2]},
        {"enabled", "asc", [w2, w1]}
      ]

      for {sort_field, direction, expected_order} <- test_cases do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w?sort=#{sort_field}&dir=#{direction}"
          )

        assert has_workflow_in_order?(view, expected_order),
               "Failed to sort by #{sort_field} in #{direction} direction"

        if direction == "asc" do
          _html =
            view
            |> element("th a[phx-value-by='#{sort_field}']")
            |> render_click()

          assert has_workflow_in_order?(view, Enum.reverse(expected_order)),
                 "Failed to reverse sort order for #{sort_field}"
        end
      end
    end

    test "combines sorting with search", %{conn: conn, project: project} do
      w1 = insert(:workflow, project: project, name: "API First")
      w2 = insert(:workflow, project: project, name: "API Second")
      _w3 = insert(:workflow, project: project, name: "Background Job")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w?q=api&sort=name&dir=desc")

      assert has_workflow_in_order?(view, [w2, w1])
      refute has_workflow_card?(view, _w3)
    end
  end

  describe "empty states" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "shows appropriate empty state message with no workflows", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/w")

      assert html =~
               "No workflows found.\n            <a href=\"/projects/#{project.id}/w/new\" data-phx-link=\"redirect\" data-phx-link-state=\"push\" class=\"link\">\n              Create one\n            </a>\n            to start automating."
    end

    test "shows appropriate empty state message when search has no results", %{
      conn: conn,
      project: project
    } do
      insert(:workflow, project: project, name: "Existing Workflow")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      html =
        view
        |> element("input[name='search_workflows']")
        |> render_keyup(%{value: "nonexistent"})

      assert html =~ "No workflows found matching"
      assert html =~ "Try a different search term"
    end

    test "switches between empty state messages", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w")

      assert html =~
               "No workflows found.\n            <a href=\"/projects/#{project.id}/w/new\" data-phx-link=\"redirect\" data-phx-link-state=\"push\" class=\"link\">\n              Create one\n            </a>\n            to start automating."

      html =
        view
        |> element("input[name='search_workflows']")
        |> render_keyup(%{value: "nonexistent"})

      assert html =~
               "No workflows found matching &quot;nonexistent&quot;. Try a different search term or"

      assert html =~
               "<a href=\"/projects/#{project.id}/w/new\" data-phx-link=\"redirect\" data-phx-link-state=\"push\" class=\"link\">\n              create a new one"

      html =
        view
        |> element("#clear_search_button")
        |> render_click()

      assert html =~
               "No workflows found.\n            <a href=\"/projects/#{project.id}/w/new\" data-phx-link=\"redirect\" data-phx-link-state=\"push\" class=\"link\">\n              Create one\n            </a>\n            to start automating."
    end
  end

  defp has_workflow_in_order?(view, workflows) do
    html = render(view)

    workflow_pattern =
      workflows
      |> Enum.map(&~r/#{&1.name}/)
      |> Enum.reduce(fn pattern, acc ->
        Regex.compile!("#{acc.source}.*#{pattern.source}", "s")
      end)

    html =~ workflow_pattern
  end
end
