defmodule LightningWeb.WorkflowLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  import Lightning.Factories
  import Lightning.WorkflowsFixtures
  import Lightning.WorkflowLive.Helpers

  alias Lightning.DashboardStats

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :create_workflow
  setup :stub_usage_limiter_ok
  setup :verify_on_exit!

  # The page is drawn by React from data-props; the texts it renders (the
  # empty states, the column headings, the badges) are tested in the design
  # system and in assets/test/design-system/WorkflowsIndexPage.test.tsx.
  @page "#workflows-index-page"

  defp props(view), do: page_props(view, @page)
  defp stats(view), do: props(view)["stats"]
  defp listed_names(view), do: Enum.map(stats(view), & &1["workflow"]["name"])

  defp row(view, workflow),
    do: Enum.find(stats(view), &(&1["workflow"]["id"] == workflow.id))

  defp toggle(view, workflow, state),
    do:
      push_page_event(view, @page, "toggle_workflow_state", %{
        "workflow_state" => state,
        "value_key" => workflow.id
      })

  defp delete_workflow(view, workflow),
    do: push_page_event(view, @page, "delete_workflow", %{"id" => workflow.id})

  defp search(view, term),
    do: push_page_event(view, @page, "search_workflows", %{"value" => term})

  # Whether `href` opens this project's History with every filter in
  # `pattern` (a regex source; brackets are literal).
  defp history_href?(href, project, pattern) do
    pattern = String.replace(pattern, "[", "\\[") |> String.replace("]", "\\]")
    Regex.match?(~r{^/projects/#{project.id}/history\?.*#{pattern}}, href)
  end

  describe "index" do
    test "lists the project's workflows", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert [%{"workflow" => %{"name" => name}}] = stats(view)
      assert name == workflow.name
    end

    test "does not intern arbitrary sort params as atoms", %{
      conn: conn,
      project: project
    } do
      # Unknown sort/dir values must not be turned into atoms, otherwise a
      # crafted URL could exhaust the BEAM atom table. Unique so no earlier test
      # could have interned them.
      bogus_key = "bogus_sort_#{System.unique_integer([:positive])}"
      bogus_dir = "bogus_dir_#{System.unique_integer([:positive])}"

      {:ok, _view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w?sort=#{bogus_key}&dir=#{bogus_dir}"
        )

      # The page loaded (defaulting to name/asc) without interning either value.
      assert_raise ArgumentError, fn -> String.to_existing_atom(bogus_key) end
      assert_raise ArgumentError, fn -> String.to_existing_atom(bogus_dir) end
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

      %{workflow: workflow} = create_workflow(%{project: project})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/w")

      assert row(view, workflow)

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

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      %{
        "metrics" => metrics,
        "pendingHref" => pending_href,
        "failedHref" => failed_href,
        "period" => "last 30 days",
        "canCreateWorkflow" => true
      } = props(view)

      # Metrics
      # 10 total workorders
      # 10 total runs (4 pending)
      # 2 successful runs out of 4 completed
      # 2 work orders failed out of 10
      assert %{
               "workOrders" => %{
                 "total" => 10,
                 "pending" => 6,
                 "failed" => 2,
                 "failedPercentage" => 20.0
               },
               "runs" => %{
                 "total" => 10,
                 "pending" => 6,
                 "success" => 2,
                 "successRate" => 50.0
               }
             } = metrics

      date = Date.to_string(DashboardStats.window_start())

      pending_and_date_filter =
        "filters[date_after]=#{date}.*&filters[log]=true&filters[pending]=true&filters[running]=true"

      assert history_href?(pending_href, project, pending_and_date_filter)

      failed_filter_pattern =
        "filters[crashed]=true&filters[date_after]=#{date}.*&filters[exception]=true&filters[failed]=true&filters[killed]=true&filters[log]=true&filters[lost]=true&filters[rejected]=true"

      assert history_href?(failed_href, project, failed_filter_pattern)
      refute history_href?(failed_href, project, "filters[success]=true")

      # Rows, in name order
      assert listed_names(view) == ["One", "Two", new_workflow.name]

      # Work orders links: the date filter without a status filter
      date_filter = "filters[date_after]=#{date}.*&filters[log]=true"

      for workflow <- [workflow1, workflow2] do
        assert %{
                 "workordersCount" => 5,
                 "failedWorkordersCount" => 1,
                 "stepCount" => 8,
                 "stepSuccessRate" => success_rate,
                 "historyHref" => history_href,
                 "failedHistoryHref" => failed_history_href,
                 "lastWorkOrder" => %{"state" => _, "updatedAt" => _},
                 "lastFailedAt" => last_failed_at
               } = row(view, workflow)

        assert success_rate == round(5 / 7 * 100 * 100) / 100
        assert last_failed_at

        assert history_href?(
                 history_href,
                 project,
                 "filters[workflow_id]=#{workflow.id}&#{date_filter}"
               )

        assert history_href?(
                 failed_history_href,
                 project,
                 "filters[workflow_id]=#{workflow.id}&#{failed_filter_pattern}"
               )
      end

      assert %{"state" => "failed"} = row(view, workflow1)["lastWorkOrder"]
      assert %{"state" => "success"} = row(view, workflow2)["lastWorkOrder"]

      # The last workflow has no activity: the page shows "Nothing last 30
      # days" and "N/A" for these.
      assert %{
               "workordersCount" => 0,
               "failedWorkordersCount" => 0,
               "lastWorkOrder" => nil,
               "lastFailedAt" => nil
             } = row(view, new_workflow)
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

        assert %{
                 "toggleTooltip" =>
                   "This workflow is inactive (manual runs only)",
                 "workflow" => %{"enabled" => false}
               } = row(view, workflow)

        assert toggle(view, workflow, "true") =~ "Workflow updated"

        assert %{
                 "toggleTooltip" => tooltip,
                 "workflow" => %{"enabled" => true}
               } = row(view, workflow)

        assert tooltip ==
                 "This workflow is active (#{trigger_type} trigger enabled)"
      end)

      # Make sure the new workflow button is enabled, even though the toggles are disabled.
      assert props(view)["canCreateWorkflow"]
    end

    test "the toggle, its tooltip and its sort all read the triggers", %{
      conn: conn,
      project: project
    } do
      on_trigger = build(:trigger, type: :webhook, enabled: true)
      off_trigger = build(:trigger, type: :cron, enabled: false)
      job = build(:job)

      workflow =
        build(:workflow, project: project, state: :live)
        |> with_job(job)
        |> with_trigger(on_trigger)
        |> with_trigger(off_trigger)
        |> with_edge({on_trigger, job})
        |> insert()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      # The switch reads "all triggers on"; the name greys out on "none on".
      assert %{
               "workflow" => %{"enabled" => false},
               "triggerEnabled" => true,
               "toggleTooltip" => "This workflow is inactive (manual runs only)"
             } = row(view, workflow)
    end

    test "toggling a workflow keeps state and triggers coherent", %{
      conn: conn,
      project: project
    } do
      trigger = build(:trigger, type: :webhook, enabled: false)
      job = build(:job)

      workflow =
        build(:workflow, project: project, state: :draft)
        |> with_job(job)
        |> with_trigger(trigger)
        |> with_edge({trigger, job})
        |> insert()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"workflow" => %{"enabled" => false}, "state" => "draft"} =
               row(view, workflow)

      assert toggle(view, workflow, "true") =~ "Workflow updated"

      assert %Lightning.Workflows.Workflow{
               state: :live,
               triggers: [%{enabled: true}]
             } =
               Lightning.Repo.get!(Lightning.Workflows.Workflow, workflow.id)
               |> Lightning.Repo.preload(:triggers)

      assert %{"workflow" => %{"enabled" => true}, "state" => "live"} =
               row(view, workflow)

      assert toggle(view, workflow, "false") =~ "Workflow updated"

      assert %Lightning.Workflows.Workflow{
               state: :draft,
               triggers: [%{enabled: false}]
             } =
               Lightning.Repo.get!(Lightning.Workflows.Workflow, workflow.id)
               |> Lightning.Repo.preload(:triggers)

      assert %{"workflow" => %{"enabled" => false}, "state" => "draft"} =
               row(view, workflow)
    end

    @tag role: :editor
    test "does not toggle a workflow outside the project", %{
      conn: conn,
      project: project
    } do
      # A workflow with an enabled trigger, in a project the user isn't in.
      other_project = insert(:project)
      trigger = build(:trigger, type: :webhook, enabled: true)
      job = build(:job)

      foreign_workflow =
        build(:workflow, project: other_project)
        |> with_job(job)
        |> with_trigger(trigger)
        |> with_edge({trigger, job})
        |> insert()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      # A foreign id, and a malformed one, are both refused without acting.
      assert toggle(view, foreign_workflow, "false") =~ "Workflow not found."

      assert toggle(view, %{id: "not-a-uuid"}, "false") =~
               "Workflow not found."

      # The foreign workflow's trigger stays enabled.
      assert Lightning.Workflows.get_workflow!(foreign_workflow.id,
               include: [:triggers]
             ).triggers
             |> Enum.all?(& &1.enabled)
    end

    test "the limiter can refuse an enable, and is not asked for a no-op one", %{
      conn: conn,
      project: project
    } do
      off_trigger = build(:trigger, type: :webhook, enabled: false)
      off_job = build(:job)

      off_workflow =
        build(:workflow, project: project)
        |> with_job(off_job)
        |> with_trigger(off_trigger)
        |> with_edge({off_trigger, off_job})
        |> insert()

      on_trigger = build(:trigger, type: :webhook, enabled: true)
      on_job = build(:job)

      on_workflow =
        build(:workflow, project: project, state: :live)
        |> with_job(on_job)
        |> with_trigger(on_trigger)
        |> with_edge({on_trigger, on_job})
        |> insert()

      asked = :counters.new(1, [:atomics])

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :activate_workflow}, _context ->
          :counters.add(asked, 1, 1)

          {:error, :too_many_workflows,
           %Lightning.Extensions.Message{text: "No more workflows"}}
        end
      )

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert toggle(view, off_workflow, "true") =~ "No more workflows"

      assert :counters.get(asked, 1) == 1

      refute Lightning.Workflows.get_workflow!(off_workflow.id,
               include: [:triggers]
             ).triggers
             |> Enum.any?(& &1.enabled)

      assert toggle(view, on_workflow, "true") =~ "Workflow updated"

      assert :counters.get(asked, 1) == 1
    end

    @tag role: :viewer
    test "viewers cannot toggle a workflow's state", %{
      conn: conn,
      project: project
    } do
      # A workflow with a disabled trigger in the viewer's own project. The
      # switch renders for viewers too, so they can click it.
      trigger = build(:trigger, type: :webhook, enabled: false)
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_job(job)
        |> with_trigger(trigger)
        |> with_edge({trigger, job})
        |> insert()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert toggle(view, workflow, "true") =~
               "You are not authorized to perform this action."

      # The click has no effect; the trigger stays disabled.
      refute Lightning.Workflows.get_workflow!(workflow.id, include: [:triggers]).triggers
             |> Enum.any?(& &1.enabled)
    end

    # The Health link is built by the page from the row's id (checked in
    # assets/test/design-system/WorkflowsIndexPage.test.tsx).
    test "each workflow row carries the ids its links are built from", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"project" => %{"id" => project_id}} = props(view)
      assert project_id == project.id
      assert %{"workflow" => %{"id" => workflow_id}} = row(view, workflow)
      assert workflow_id == workflow.id
    end
  end

  describe "the lifecycle column" do
    setup %{user: user} do
      user =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Lightning.Repo.update!()

      %{user: user}
    end

    test "reports the state and offers no switch on an ordinary project", %{
      conn: conn,
      project: project,
      user: user,
      workflow: workflow
    } do
      {:ok, _workflow} =
        Lightning.Workflows.go_live(
          Lightning.Repo.preload(workflow, :triggers),
          user
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"lifecycle" => true, "project" => %{"parentId" => nil}} =
               props(view)

      assert %{"state" => "live"} = row(view, workflow)
    end

    test "keeps the switch inside a sandbox", %{conn: conn, user: user} do
      parent = insert(:project, project_users: [%{user: user, role: :owner}])

      sandbox =
        insert(:project,
          parent_id: parent.id,
          project_users: [%{user: user, role: :owner}]
        )

      workflow = insert(:simple_workflow, project: sandbox)

      {:ok, view, _html} = live(conn, ~p"/projects/#{sandbox.id}/w")

      assert %{"lifecycle" => true, "project" => %{"parentId" => parent_id}} =
               props(view)

      assert parent_id == parent.id

      # The switch speaks of the state here, not of the triggers.
      assert %{"toggleTooltip" => "Off. Its triggers are not answering."} =
               row(view, workflow)
    end

    test "is the list from before the lifecycle without the flag", %{
      conn: conn,
      project: project,
      user: user,
      workflow: workflow
    } do
      user
      |> Ecto.Changeset.change(%{preferences: %{}})
      |> Lightning.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"lifecycle" => false} = props(view)

      assert %{
               "toggleTooltip" =>
                 "This workflow is active (webhook trigger enabled)"
             } =
               row(view, workflow)
    end
  end

  describe "creating workflows" do
    @tag role: :viewer
    test "users with viewer role cannot create a workflow", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"canCreateWorkflow" => false} = props(view)
    end

    @tag role: :editor
    test "users with editor role can create a workflow", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"canCreateWorkflow" => true} = props(view)

      # the collaborative editor mounts for new workflows
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new")

      assert html =~ "collaborative-editor-react"
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

      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/w")

      assert %{"canCreateWorkflow" => true} = props(view)

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

      assert %{"canDeleteWorkflow" => false} = props(view)

      assert delete_workflow(view, workflow) =~
               "You are not authorized to perform this action."

      assert Lightning.Repo.reload(workflow).deleted_at == nil
    end

    @tag role: :editor
    test "users with editor role can delete a workflow", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"canDeleteWorkflow" => true} = props(view)
      assert row(view, workflow)

      assert delete_workflow(view, workflow) =~ "Workflow successfully deleted."

      refute row(view, workflow)
    end

    @tag role: :editor
    test "audits when a workflow has been marked for deletion", %{
      conn: conn,
      project: project,
      user: %{id: user_id},
      workflow: %{id: workflow_id} = workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      delete_workflow(view, workflow)

      audit = Lightning.Repo.one(Lightning.Auditing.Audit)

      assert %{
               event: "marked_for_deletion",
               item_id: ^workflow_id,
               actor_id: ^user_id
             } = audit
    end

    @tag role: :editor
    test "does not delete a workflow outside the project", %{
      conn: conn,
      project: project
    } do
      # A workflow in a project the user isn't in, even though they can delete
      # in their own project.
      other_project = insert(:project)
      foreign_workflow = insert(:workflow, project: other_project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      # A foreign id, and a malformed one, are both refused without acting.
      assert delete_workflow(view, foreign_workflow) =~ "Workflow not found."
      assert delete_workflow(view, %{id: "not-a-uuid"}) =~ "Workflow not found."

      # The foreign workflow is not marked for deletion.
      assert Lightning.Repo.reload(foreign_workflow).deleted_at == nil
    end
  end

  describe "search workflows" do
    test "filters workflows by search term", %{conn: conn, project: project} do
      insert(:workflow, project: project, name: "API Gateway")
      insert(:workflow, project: project, name: "Background Jobs")
      insert(:workflow, project: project, name: "REST API")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w?q=api")

      assert listed_names(view) == ["API Gateway", "REST API"]
      assert %{"searchTerm" => "api"} = props(view)
    end

    test "clears search term", %{conn: conn, project: project} do
      insert(:workflow, project: project, name: "API Gateway")
      insert(:workflow, project: project, name: "Background Jobs")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w?q=api")

      push_page_event(view, @page, "clear_search")

      assert_patch(view, ~p"/projects/#{project.id}/w?sort=name&dir=asc")
      assert "Background Jobs" in listed_names(view)
      assert %{"searchTerm" => ""} = props(view)
    end

    test "updates search in real-time", %{conn: conn, project: project} do
      insert(:workflow, project: project, name: "API Gateway")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      search(view, "api")

      assert_patch(view, ~p"/projects/#{project.id}/w?sort=name&dir=asc&q=api")
      assert listed_names(view) == ["API Gateway"]
    end

    test "sends the search term with an empty list, so the page can say so", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w?q=nonexistent")

      assert %{"searchTerm" => "nonexistent", "stats" => []} = props(view)
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

        # The setup's own workflow is listed too; only these two are compared.
        names = fn ->
          Enum.filter(listed_names(view), &(&1 in [w1.name, w2.name]))
        end

        assert names.() == Enum.map(expected_order, & &1.name),
               "Failed to sort by #{sort_field} in #{direction} direction"

        assert %{"sort" => %{"key" => ^sort_field, "direction" => ^direction}} =
                 props(view)
      end
    end

    test "combines sorting with search", %{conn: conn, project: project} do
      insert(:workflow, project: project, name: "API First")
      insert(:workflow, project: project, name: "API Second")
      insert(:workflow, project: project, name: "Background Job")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w?q=api&sort=name&dir=desc")

      assert listed_names(view) == ["API Second", "API First"]
    end
  end

  describe "empty states" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "sends an empty list with no search term", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"stats" => [], "searchTerm" => ""} = props(view)
    end

    test "sends an empty list with the search term when nothing matches", %{
      conn: conn,
      project: project
    } do
      insert(:workflow, project: project, name: "Existing Workflow")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      search(view, "nonexistent")

      assert %{"stats" => [], "searchTerm" => "nonexistent"} = props(view)
    end

    test "switches between empty states", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert %{"stats" => [], "searchTerm" => ""} = props(view)

      search(view, "nonexistent")

      assert %{"stats" => [], "searchTerm" => "nonexistent"} = props(view)

      push_page_event(view, @page, "clear_search")

      assert %{"stats" => [], "searchTerm" => ""} = props(view)
    end
  end
end
