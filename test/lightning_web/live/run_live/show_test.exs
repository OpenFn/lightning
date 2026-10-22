defmodule LightningWeb.RunLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import LightningWeb.DesignSystemHelpers

  alias Lightning.WorkOrders

  @page "#run-show-page"

  setup :stub_rate_limiter_ok

  describe "cross-project access" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "redirects to project history when the run belongs to another project",
         %{conn: conn, project: project} do
      run = run_in_project(insert(:project))

      assert {:error, {:redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/projects/#{project.id}/runs/#{run.id}")

      assert to == ~p"/projects/#{project.id}/history"
      assert flash["error"] == "Run not found"
    end

    test "redirects to project history when the run does not exist", %{
      conn: conn,
      project: project
    } do
      assert {:error, {:redirect, %{to: to, flash: flash}}} =
               live(
                 conn,
                 ~p"/projects/#{project.id}/runs/#{Ecto.UUID.generate()}"
               )

      assert to == ~p"/projects/#{project.id}/history"
      assert flash["error"] == "Run not found"
    end
  end

  defp run_in_project(project) do
    %{triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project)

    work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: insert(:dataclip)
      )

    insert(:run,
      work_order: work_order,
      starting_trigger: trigger,
      dataclip: insert(:dataclip)
    )
  end

  describe "handle_async/3" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "lifecycle of a run", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}], jobs: [job_a, job_b | _rest]} =
        workflow = insert(:complex_workflow, project: project) |> with_snapshot()

      # Post to webhook
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      workorder =
        %{runs: [%{id: run_id} = run]} =
        WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      # The run is loaded after the mount; the page knows its id from the start.
      assert page_props(view, @page)["runId"] == run_id

      # The page says it is listening before the run has loaded.
      push_page_event(view, @page, "logs_ready", %{})
      assert_reply(view, %{})

      render_async(view)

      props = page_props(view, @page)
      assert props["loading"] == false
      assert props["run"]["id"] == run_id
      assert props["run"]["state"] == "available", "has enqueued state"
      assert props["run"]["startedBy"] == "Webhook trigger"
      assert props["workflow"]["name"] == workflow.name
      assert props["steps"] == [], "has no steps"
      assert props["selectedStepId"] == nil

      run =
        Lightning.Repo.update!(
          run
          |> Ecto.Changeset.change(%{
            state: :claimed,
            claimed_at: DateTime.utc_now()
          })
        )

      Lightning.Runs.start_run(run)

      assert page_props(view, @page)["run"]["state"] == "started",
             "has running state"

      {:ok, step} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job_a.id,
          input_dataclip_id: input_dataclip_id = workorder.dataclip_id
        })

      assert [step_props] = page_props(view, @page)["steps"]
      assert step_props["id"] == step.id
      assert step_props["jobName"] == job_a.name
      assert step_props["startedAt"] == DateTime.to_iso8601(step.started_at)
      assert step_props["exitReason"] == nil

      {:ok, log_line_1} = add_log(run, ["I'm the worker, I'm working!"])

      {:ok, log_line_2} = add_log({run, step}, %{message: "hello"})

      event_name = "logs-#{run.id}"

      assert_push_event(view, ^event_name, %{logs: [^log_line_1]})
      assert_push_event(view, ^event_name, %{logs: [^log_line_2]})

      view |> select_step(project, run, step)

      props = page_props(view, @page)
      assert props["selectedStepId"] == step.id

      assert props["inputDataclip"] == %{
               "id" => input_dataclip_id,
               "wiped" => false
             }

      assert props["outputDataclip"] == nil

      # Complete the step
      {:ok, step} =
        Lightning.Runs.complete_step(%{
          run_id: run_id,
          project_id: project.id,
          step_id: step.id,
          output_dataclip: %{"y" => 2},
          output_dataclip_id: output_dataclip_id = Ecto.UUID.generate(),
          reason: "success"
        })

      props = page_props(view, @page)
      assert props["outputDataclip"]["id"] == output_dataclip_id
      assert [%{"exitReason" => "success"}] = props["steps"]

      {:ok, step_2} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job_b.id,
          input_dataclip_id: output_dataclip_id
        })

      assert [%{"jobName" => name_a}, %{"jobName" => name_b}] =
               page_props(view, @page)["steps"]

      assert {name_a, name_b} == {job_a.name, job_b.name}

      view |> select_step(project, run, step_2)

      props = page_props(view, @page)
      assert props["inputDataclip"]["id"] == output_dataclip_id
      assert props["outputDataclip"] == nil

      {:ok, _step_2} =
        Lightning.Runs.complete_step(%{
          run_id: run_id,
          project_id: project.id,
          step_id: step_2.id,
          output_dataclip: %{"z" => 2},
          output_dataclip_id: step_2_output_dataclip_id = Ecto.UUID.generate(),
          reason: "success"
        })

      assert page_props(view, @page)["outputDataclip"]["id"] ==
               step_2_output_dataclip_id

      # Go back to the previous step and check the output gets switched back
      view |> select_step(project, run, step)

      assert page_props(view, @page)["outputDataclip"]["id"] ==
               output_dataclip_id

      # A step the run does not have shows neither of the previous step's dataclips
      render_patch(view, ~p"/projects/#{project.id}/runs/#{run_id}?step=nope")

      props = page_props(view, @page)
      assert props["selectedStepId"] == "nope"
      assert props["inputDataclip"] == nil
      assert props["outputDataclip"] == nil

      {:ok, _} = Lightning.Runs.complete_run(run, %{state: "failed"})

      props = page_props(view, @page)
      assert props["run"]["state"] == "failed"
      assert props["run"]["finalDataclipId"] == nil
      refute is_nil(props["run"]["finishedAt"])
    end

    test "shows final output when run completes with a final_dataclip_id", %{
      conn: conn,
      project: project
    } do
      %{triggers: [%{id: webhook_trigger_id}], jobs: [job | _rest]} =
        insert(:complex_workflow, project: project) |> with_snapshot()

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id} = run]} =
        workorder = WorkOrders.get(wo_id, include: [:runs])

      run =
        Lightning.Repo.update!(
          Ecto.Changeset.change(run, %{
            state: :claimed,
            claimed_at: DateTime.utc_now()
          })
        )

      Lightning.Runs.start_run(run)

      {:ok, step} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job.id,
          input_dataclip_id: workorder.dataclip_id
        })

      {:ok, _step} =
        Lightning.Runs.complete_step(%{
          run_id: run_id,
          project_id: project.id,
          step_id: step.id,
          output_dataclip: %{"result" => 42},
          output_dataclip_id: output_dataclip_id = Ecto.UUID.generate(),
          reason: "success"
        })

      {:ok, _} =
        Lightning.Runs.complete_run(run, %{
          state: "success",
          final_dataclip_id: output_dataclip_id
        })

      {:ok, %{id: stored_line_id}} = add_log(run, ["stored before the visit"])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      render_async(view)

      assert page_props(view, @page)["run"]["finalDataclipId"] ==
               output_dataclip_id

      # The stored lines are streamed once the page says it is listening.
      event_name = "logs-#{run_id}"

      push_page_event(view, @page, "logs_ready", %{})
      assert_reply(view, %{})
      assert_push_event(view, ^event_name, %{logs: [%{id: ^stored_line_id}]})
    end

    @tag role: :viewer
    test "names the project admins only when a wiped dataclip is showing", %{
      conn: conn,
      project: project
    } do
      insert(:project_user,
        project: project,
        user: insert(:user, email: "admin@example.org"),
        role: :admin
      )

      %{triggers: [%{id: webhook_trigger_id}], jobs: [job | _rest]} =
        insert(:complex_workflow, project: project) |> with_snapshot()

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id} = run]} =
        workorder = WorkOrders.get(wo_id, include: [:runs])

      run =
        Lightning.Repo.update!(
          Ecto.Changeset.change(run, %{
            state: :claimed,
            claimed_at: DateTime.utc_now()
          })
        )

      Lightning.Runs.start_run(run)

      {:ok, step} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job.id,
          input_dataclip_id: workorder.dataclip_id
        })

      Lightning.Invocation.Dataclip
      |> Lightning.Repo.get!(workorder.dataclip_id)
      |> Ecto.Changeset.change(
        wiped_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Lightning.Repo.update!()

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      render_async(view)

      props = page_props(view, @page)
      assert props["canEditDataRetention"] == false
      assert props["adminContacts"] == []

      render_patch(
        view,
        ~p"/projects/#{project.id}/runs/#{run_id}?step=#{step.id}"
      )

      props = page_props(view, @page)
      assert props["inputDataclip"]["wiped"] == true
      assert "admin@example.org" in props["adminContacts"]
    end

    test "a step id the run does not have selects nothing", %{
      conn: conn,
      project: project
    } do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project) |> with_snapshot()

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}]} = WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}?step=nope")

      render_async(view)

      props = page_props(view, @page)
      assert props["selectedStepId"] == "nope"
      assert props["inputDataclip"] == nil
      assert props["outputDataclip"] == nil
    end
  end

  defp add_log({run, step}, message) do
    Lightning.Runs.append_run_log(run, %{
      step_id: step.id,
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  defp add_log(run, message) do
    Lightning.Runs.append_run_log(run, %{
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  describe "workflow link" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    # The page builds the editor link from the run's snapshot version, the
    # workflow's, and whether the user has experimental features.
    test "sends the versions the page pins the editor link with", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()
      %{triggers: [%{id: webhook_trigger_id}]} = workflow

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}], snapshot: snapshot} =
        WorkOrders.get(wo_id, include: [:runs, :snapshot])

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")
      render_async(view)

      props = page_props(view, @page)
      assert props["workflow"]["id"] == workflow.id
      assert props["workflow"]["lockVersion"] == workflow.lock_version
      assert props["run"]["snapshot"]["id"] == snapshot.id
      assert props["run"]["snapshot"]["lockVersion"] == snapshot.lock_version
      assert props["experimentalFeatures"] == false
    end

    test "sends the newer workflow version when the run's snapshot is older",
         %{conn: conn, project: project, user: user} do
      Lightning.Accounts.update_user_preference(
        user,
        "experimental_features",
        true
      )

      workflow =
        insert(:simple_workflow, project: project, lock_version: 1)
        |> with_snapshot()

      %{triggers: [%{id: webhook_trigger_id}]} = workflow

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}], snapshot: snapshot} =
        WorkOrders.get(wo_id, include: [:runs, :snapshot])

      Lightning.Repo.update!(Ecto.Changeset.change(workflow, lock_version: 2))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")
      render_async(view)

      props = page_props(view, @page)
      assert props["workflow"]["lockVersion"] == 2
      assert props["run"]["snapshot"]["lockVersion"] == snapshot.lock_version
      assert props["experimentalFeatures"] == true
    end
  end

  describe "cancel run" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "the page may offer Cancel on an enqueued run the user may run",
         %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project) |> with_snapshot()

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}]} = WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      render_async(view)

      props = page_props(view, @page)
      assert props["run"]["state"] == "available"
      assert props["canRunWorkflow"] == true
    end

    @tag role: :viewer
    test "a viewer may not run, and is refused on the server too",
         %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project) |> with_snapshot()

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}]} = WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      render_async(view)

      assert page_props(view, @page)["canRunWorkflow"] == false

      push_page_event(view, @page, "cancel_run", %{})

      assert_reply(view, %{
        error: "You are not authorized to perform this action."
      })

      assert page_props(view, @page)["run"]["state"] == "available"
    end

    test "cancelling transitions the run to cancelled and flashes",
         %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project) |> with_snapshot()

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}]} = WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      render_async(view)

      # The run cancelled is this page's, whatever id the browser sends.
      html =
        push_page_event(view, @page, "cancel_run", %{
          "run_id" => Ecto.UUID.generate()
        })

      assert_reply(view, %{})
      assert html =~ "Run cancelled."
      assert page_props(view, @page)["run"]["state"] == "cancelled"
    end

    test "cancel when run already claimed shows graceful flash",
         %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project) |> with_snapshot()

      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id} = run]} = WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      render_async(view)

      # Claim the run behind the scenes
      Lightning.Repo.update!(
        Ecto.Changeset.change(run, %{
          state: :claimed,
          claimed_at: DateTime.utc_now()
        })
      )

      html = push_page_event(view, @page, "cancel_run", %{})

      assert_reply(view, %{})
      assert html =~ "already been claimed"
    end
  end

  describe "log level" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "remembers a level the viewer picks, and refuses one it does not know",
         %{conn: conn, project: project, user: user} do
      run = run_in_project(project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run.id}")

      assert page_props(view, @page)["logLevel"] == "info"

      push_page_event(view, @page, "save_log_level", %{"level" => "debug"})
      assert_reply(view, %{})
      assert page_props(view, @page)["logLevel"] == "debug"

      assert Lightning.Repo.reload!(user).preferences["desired_log_level"] ==
               "debug"

      push_page_event(view, @page, "save_log_level", %{"level" => "loud"})
      assert_reply(view, %{error: "Invalid request"})

      push_page_event(view, @page, "save_log_level", %{})
      assert_reply(view, %{error: "Invalid request"})

      assert page_props(view, @page)["logLevel"] == "debug"
    end
  end

  defp select_step(view, project, run, step) do
    render_patch(
      view,
      ~p"/projects/#{project.id}/runs/#{run.id}?step=#{step.id}"
    )
  end
end
