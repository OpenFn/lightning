defmodule LightningWeb.WorkflowLive.EditorTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.WorkflowLive.Helpers
  import Lightning.Factories

  import Ecto.Query

  alias Lightning.Invocation
  alias Lightning.Workflows.Workflow

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :create_workflow

  test "can edit a jobs body", %{
    project: project,
    workflow: workflow,
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

    job = workflow.jobs |> List.first()

    view |> select_node(job)

    view |> job_panel_element(job)

    assert view |> job_panel_element(job) |> render() =~ "First Job",
           "can see the job name in the panel"

    view |> click_edit(job)

    assert view |> job_edit_view(job) |> has_element?(),
           "can see the job_edit_view component"
  end

  test "mounts the JobEditor with the correct attrs", %{
    conn: conn,
    project: project,
    workflow: workflow
  } do
    project_credential =
      insert(:project_credential,
        project: project,
        credential:
          build(:credential,
            name: "dummytestcred",
            schema: "http",
            body: %{
              username: "test",
              password: "test"
            }
          )
      )

    job = workflow.jobs |> hd()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
      )

    actual_attrs =
      view
      |> element("div[phx-hook='JobEditor']")
      |> render()
      |> Floki.parse_fragment!()
      |> Enum.at(0)
      |> then(fn {_, attrs, _} ->
        Map.new(attrs)
      end)

    # The JobEditor component should be mounted with a resolved version number
    assert job.adaptor == "@openfn/language-common@latest"
    assert {"data-adaptor", "@openfn/language-common@1.6.2"} in actual_attrs

    assert {"data-change-event", "job_body_changed"} in actual_attrs
    assert {"data-disabled", "false"} in actual_attrs
    assert {"data-source", job.body} in actual_attrs
    assert {"id", "job-editor-#{job.id}"} in actual_attrs
    assert {"phx-hook", "JobEditor"} in actual_attrs
    assert {"phx-target", "1"} in actual_attrs
    assert {"phx-update", "ignore"} in actual_attrs

    # try changing the assigned credential

    credential_block =
      element(view, "#modal-header-credential-block") |> render()

    assert credential_block =~ "No Credential"
    refute credential_block =~ project_credential.credential.name

    view
    |> form("#workflow-form",
      workflow: %{
        jobs: %{
          "0" => %{
            "project_credential_id" => project_credential.id
          }
        }
      }
    )
    |> render_change()

    credential_block =
      element(view, "#modal-header-credential-block") |> render()

    refute credential_block =~ "No Credential"
    assert credential_block =~ project_credential.credential.name
  end

  describe "manual runs" do
    @tag role: :viewer
    test "viewers can't run a job", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      job = workflow.jobs |> hd()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
        )

      # dataclip dropdown is disabled
      assert view
             |> element(
               ~s{#manual-job-#{job.id} form select[name='manual[dataclip_id]'][disabled]}
             )
             |> has_element?()

      assert view
             |> element(
               ~s{button[type='submit'][form='manual_run_form'][disabled]}
             )
             |> has_element?()

      assert view |> render_click("manual_run_submit", %{"manual" => %{}}) =~
               "You are not authorized to perform this action."
    end

    test "can see the last 3 dataclips", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      job = workflow.jobs |> hd()

      dataclip_ids =
        insert_list(4, :step,
          job: job,
          inserted_at: fn ->
            ExMachina.sequence(:past_timestamp, fn i ->
              DateTime.utc_now() |> DateTime.add(-i)
            end)
          end
        )
        |> Enum.map(fn step ->
          step.input_dataclip_id
        end)
        |> Enum.reverse()

      # wiped dataclip. This is the latest dataclip
      wiped_dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

      insert(:step, job: job, input_dataclip: wiped_dataclip)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
        )

      assert view
             |> element(
               ~s{#manual-job-#{job.id} form select[name='manual[dataclip_id]'] option},
               "Create a new input"
             )
             |> has_element?()

      for dataclip_id <- dataclip_ids |> Enum.slice(0..2) do
        assert view
               |> element(
                 ~s{#manual-job-#{job.id} form select[name='manual[dataclip_id]'] option},
                 dataclip_id
               )
               |> has_element?()
      end

      # wiped dataclip is not listed despite being latest
      refute view
             |> element(
               ~s{#manual-job-#{job.id} form select[name='manual[dataclip_id]'] option},
               wiped_dataclip.id
             )
             |> has_element?()
    end

    test "can create a new input dataclip", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      assert Invocation.list_dataclips_for_job(job) |> Enum.count() == 0

      body = %{"a" => 1}

      view
      |> form("#manual-job-#{job.id} form",
        manual: %{
          body: Jason.encode!(body)
        }
      )
      |> render_submit()

      assert where(
               Lightning.Invocation.Dataclip,
               [d],
               d.body == ^body and d.type == :saved_input and
                 d.project_id == ^p.id
             )
             |> Lightning.Repo.exists?()
    end

    @tag role: :editor
    test "can't with a new dataclip if it's invalid", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      view
      |> form("#manual-job-#{job.id} form", %{
        "manual" => %{"body" => "1"}
      })
      |> render_change()

      assert view
             |> has_element?("#manual-job-#{job.id} form", "Must be an object")

      view
      |> form("#manual-job-#{job.id} form", %{
        "manual" => %{"body" => "]"}
      })
      |> render_change()

      assert view |> has_element?("#manual-job-#{job.id} form", "Invalid JSON")
    end

    test "can run a job", %{conn: conn, project: p, workflow: w} do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      assert view
             |> element(
               "button[type='submit'][form='manual_run_form'][disabled]"
             )
             |> has_element?()

      view
      |> form("#manual-job-#{job.id} form", %{
        "manual" => %{"body" => "{}"}
      })
      |> render_change()

      refute view
             |> element(
               "button[type='submit'][form='manual_run_form'][disabled]"
             )
             |> has_element?()

      assert [] == live_children(view)

      view
      |> element("#manual-job-#{job.id} form")
      |> render_submit()

      assert [run_viewer] = live_children(view)

      render_async(run_viewer)

      assert run_viewer
             |> element("li:nth-child(5) dd", "Enqueued")
             |> has_element?()
    end

    test "the new dataclip is selected after running job", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      existing_dataclip = insert(:dataclip, project: p)

      insert(:workorder,
        workflow: w,
        dataclip: existing_dataclip,
        runs: [
          build(:run,
            dataclip: existing_dataclip,
            starting_job: job,
            steps: [build(:step, job: job, input_dataclip: existing_dataclip)]
          )
        ]
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      body = %{"val" => Ecto.UUID.generate()}

      dataclip_query =
        where(
          Lightning.Invocation.Dataclip,
          [d],
          d.type == :saved_input and
            d.project_id == ^p.id
        )

      refute Lightning.Repo.exists?(dataclip_query)
      refute render(view) =~ body["val"]

      view
      |> form("#manual-job-#{job.id} form", %{
        manual: %{body: Jason.encode!(body)}
      })
      |> render_submit()

      assert render(view) =~ body["val"]

      new_dataclip = Lightning.Repo.one(dataclip_query)

      element =
        view
        |> element(
          "select#manual_run_form_dataclip_id option[value='#{new_dataclip.id}']"
        )

      assert render(element) =~ "selected"

      refute view
             |> element("save-and-run", ~c"Create New Work Order")
             |> has_element?()
    end

    test "creating a work order from a newly created job should save the workflow first",
         %{
           conn: conn,
           project: project
         } do
      workflow =
        insert(:workflow, project: project)
        |> Lightning.Repo.preload([:jobs, :work_orders])

      new_job_name = "new job"

      assert workflow.jobs |> Enum.count() === 0

      assert workflow.jobs |> Enum.find(fn job -> job.name === new_job_name end) ===
               nil

      assert workflow.work_orders |> Enum.count() === 0

      %{"value" => %{"id" => job_id}} =
        job_patch = add_job_patch(new_job_name)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/w/#{workflow}")

      # add a job to it but don't save
      view |> push_patches_to_view([job_patch])

      view |> select_node(%{id: job_id})

      view |> click_edit(%{id: job_id})

      view |> change_editor_text("some body")

      view
      |> form("#manual_run_form", %{
        manual: %{body: Jason.encode!(%{})}
      })
      |> render_submit()

      workflow =
        Lightning.Repo.get!(Workflow, workflow.id)
        |> Lightning.Repo.preload([:jobs, :work_orders])

      assert workflow.jobs |> Enum.count() === 1

      assert workflow.jobs
             |> Enum.find(fn job -> job.name === new_job_name end)
             |> Map.get(:name) === new_job_name

      assert workflow.work_orders |> Enum.count() === 1
    end

    test "creating a workorder from a newly created workflow and job saves the workflow first",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :admin}])

      workflow_name = "mytest workflow"
      job_name = "my job"

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/new?#{%{name: workflow_name}}")

      # add a job to the workflow
      %{"value" => %{"id" => job_id}} = job_patch = add_job_patch(job_name)

      view |> push_patches_to_view([job_patch])

      # select job node
      view |> select_node(%{id: job_id})

      # open the editor modal
      view |> click_edit(%{id: job_id})

      view |> change_editor_text("some body")

      # no workflow exists
      refute Lightning.Repo.get_by(Lightning.Workflows.Workflow,
               project_id: project.id
             )

      # submit the manual run form
      view
      |> form("#manual_run_form", %{
        manual: %{body: Jason.encode!(%{})}
      })
      |> render_submit()

      # workflow has been created
      assert workflow =
               Lightning.Repo.get_by(Lightning.Workflows.Workflow,
                 project_id: project.id
               )
               |> Lightning.Repo.preload([:jobs, :work_orders])

      assert workflow.name == workflow_name

      assert Enum.any?(workflow.jobs, fn job ->
               job.id == job_id and job.name == job_name
             end)

      assert length(workflow.work_orders) == 1
    end

    test "retry a work order saves the workflow first", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      dataclip = insert(:dataclip, type: :http_request)

      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          dataclip: dataclip,
          state: :failed,
          runs: [
            build(:run,
              dataclip: dataclip,
              starting_job: job_1,
              state: :failed,
              steps: [
                build(:step,
                  job: job_1,
                  input_dataclip: dataclip,
                  output_dataclip: build(:dataclip),
                  exit_reason: "fail",
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp)
                )
              ]
            )
          ]
        )

      assert job_1.body === "fn(state => { return {...state, extra: \"data\"} })"

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1.id, a: run.id, m: "expand"]}"
        )

      view
      |> change_editor_text("fn(state => state)")

      view
      |> element("#save-and-run", "Rerun from here")
      |> render_click()

      workflow =
        Lightning.Repo.reload(workflow) |> Lightning.Repo.preload([:jobs])

      job_1 = workflow.jobs |> Enum.find(fn job -> job.id === job_1.id end)
      assert job_1.body !== "fn(state => { return {...state, extra: \"data\"} })"
      assert job_1.body === "fn(state => state)"
    end

    test "selects the input dataclip for the step if a run is followed",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1, job_2 | _rest]} = workflow
         } do
      input_dataclip = insert(:dataclip, project: project, type: :http_request)

      output_dataclip =
        insert(:dataclip,
          project: project,
          type: :step_result,
          body: %{"val" => Ecto.UUID.generate()}
        )

      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          dataclip: input_dataclip,
          runs: [
            build(:run,
              dataclip: input_dataclip,
              starting_job: job_1,
              steps: [
                build(:step,
                  job: job_1,
                  input_dataclip: input_dataclip,
                  output_dataclip: output_dataclip,
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success"
                ),
                build(:step,
                  job: job_2,
                  input_dataclip: output_dataclip,
                  output_dataclip:
                    build(:dataclip,
                      type: :step_result,
                      body: %{}
                    ),
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success"
                )
              ]
            )
          ]
        )

      # insert 3 new dataclips
      dataclips = insert_list(3, :dataclip, project: project)

      # associate dataclips with job 2
      for dataclip <- dataclips do
        insert(:workorder,
          workflow: workflow,
          dataclip: dataclip,
          runs: [
            build(:run,
              dataclip: dataclip,
              starting_job: job_2,
              steps: [
                build(:step,
                  job: job_2,
                  input_dataclip: dataclip,
                  output_dataclip: nil,
                  started_at: build(:timestamp),
                  finished_at: nil,
                  exit_reason: nil
                )
              ]
            )
          ]
        )
      end

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_2.id, a: run.id, m: "expand"]}"
        )

      # the step dataclip is different from the run dataclip.
      # this assertion means that the run dataclip won't be selected
      refute run.dataclip_id == output_dataclip.id

      # the form has the dataclips body
      assert element(view, "#manual-job-#{job_2.id} form") |> render() =~
               output_dataclip.body["val"]

      # the step dataclip is selected
      element =
        view
        |> element(
          "select#manual_run_form_dataclip_id  option[value='#{output_dataclip.id}']"
        )

      assert render(element) =~ "selected"
    end

    test "selects the input dataclip for the run if no step has been added yet",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1 | _rest]} = workflow
         } do
      input_dataclip = insert(:dataclip, project: project, type: :http_request)

      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          dataclip: input_dataclip,
          runs: [
            build(:run,
              dataclip: input_dataclip,
              starting_job: job_1,
              steps: []
            )
          ]
        )

      # insert 3 new dataclips
      dataclips = insert_list(3, :dataclip, project: project)

      # associate dataclips with job 1
      for dataclip <- dataclips do
        insert(:workorder,
          workflow: workflow,
          dataclip: dataclip,
          runs: [
            build(:run,
              dataclip: dataclip,
              starting_job: job_1,
              steps: [
                build(:step,
                  job: job_1,
                  input_dataclip: dataclip,
                  output_dataclip: nil,
                  started_at: build(:timestamp),
                  finished_at: nil,
                  exit_reason: nil
                )
              ]
            )
          ]
        )
      end

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1.id, a: run.id, m: "expand"]}"
        )

      # the form has the dataclip
      assert element(view, "#manual-job-#{job_1.id} form") |> render() =~
               input_dataclip.id

      # the run dataclip is selected
      element =
        view
        |> element(
          "select#manual_run_form_dataclip_id  option[value='#{input_dataclip.id}']"
        )

      assert render(element) =~ "selected"
    end

    test "does not show the dataclip select input if the step dataclip is not available",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1 | _rest]} = workflow
         } do
      input_dataclip = insert(:dataclip, project: project, type: :http_request)

      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          dataclip: input_dataclip,
          runs: [
            build(:run,
              dataclip: input_dataclip,
              starting_job: job_1,
              steps: [
                build(:step,
                  job: job_1,
                  input_dataclip: nil,
                  output_dataclip: nil,
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success"
                )
              ]
            )
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1.id, a: run.id, m: "expand"]}"
        )

      # notice that we haven't wiped the run dataclip.
      # This is intentional to assert that we dont EVER fallback to the run dataclip
      # if we dont find a dataclip on the step
      assert is_nil(input_dataclip.wiped_at)

      # the form does not contain the dataclip
      form = element(view, "#manual-job-#{job_1.id} form")
      refute render(form) =~ input_dataclip.id

      # the select input doesn't exist
      refute has_element?(view, "select#manual_run_form_dataclip_id")

      assert render(form) =~ "data for this step has not been retained"

      # user can click to show the dataclip selector
      assert has_element?(view, "#toggle_dataclip_selector_button")

      view |> element("#toggle_dataclip_selector_button") |> render_click()

      # the select input now exists
      assert has_element?(view, "select#manual_run_form_dataclip_id")

      # the wiped message is nolonger displayed
      refute render(form) =~ "data for this step has not been retained"

      assert has_element?(view, "textarea#manual_run_form_body")
    end

    test "users can retry a workorder from a followed run",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1, job_2 | _rest]} = workflow
         } do
      input_dataclip = insert(:dataclip, project: project, type: :http_request)

      output_dataclip =
        insert(:dataclip,
          project: project,
          type: :step_result,
          body: %{"val" => Ecto.UUID.generate()}
        )

      %{runs: [run]} =
        workorder =
        insert(:workorder,
          workflow: workflow,
          dataclip: input_dataclip,
          state: :success,
          runs: [
            build(:run,
              dataclip: input_dataclip,
              starting_job: job_1,
              state: :success,
              steps: [
                build(:step,
                  job: job_1,
                  input_dataclip: input_dataclip,
                  output_dataclip: output_dataclip,
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success"
                ),
                build(:step,
                  job: job_2,
                  input_dataclip: output_dataclip,
                  output_dataclip:
                    build(:dataclip,
                      type: :step_result,
                      body: %{}
                    ),
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success"
                )
              ]
            )
          ]
        )

      # insert 3 new dataclips
      dataclips = insert_list(3, :dataclip, project: project)

      # associate dataclips with job 2
      for dataclip <- dataclips do
        insert(:workorder,
          workflow: workflow,
          dataclip: dataclip,
          runs: [
            build(:run,
              dataclip: dataclip,
              starting_job: job_2,
              steps: [
                build(:step,
                  job: job_2,
                  input_dataclip: dataclip,
                  output_dataclip: nil,
                  started_at: build(:timestamp),
                  finished_at: nil,
                  exit_reason: nil
                )
              ]
            )
          ]
        )
      end

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_2.id, a: run.id, m: "expand"]}"
        )

      # user gets option to rerun
      assert has_element?(view, "button", "Rerun from here")
      assert has_element?(view, "button", "Create New Work Order")

      # if we choose a different dataclip, the retry button disappears
      view
      |> form("#manual_run_form", manual: %{dataclip_id: hd(dataclips).id})
      |> render_change()

      refute has_element?(view, "button", "Rerun from here")
      assert has_element?(view, "button", "Create New Work Order")

      # if we choose the step input dataclip, the retry button becomes available
      step = Enum.find(run.steps, fn step -> step.job_id == job_2.id end)

      view
      |> form("#manual_run_form", manual: %{dataclip_id: step.input_dataclip_id})
      |> render_change()

      assert has_element?(view, "button", "Rerun from here")
      assert has_element?(view, "button", "Create New Work Order")

      view |> element("button", "Rerun from here") |> render_click()

      all_runs =
        Lightning.Repo.preload(workorder, [:runs], force: true).runs

      assert Enum.count(all_runs) == 2
      [new_run] = Enum.reject(all_runs, fn a -> a.id == run.id end)

      html = render(view)

      refute html =~ run.id
      assert html =~ new_run.id
    end

    test "followed run with wiped dataclip renders the page correctly",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1, job_2 | _rest]} = workflow
         } do
      wiped_dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: nil,
          wiped_at: DateTime.utc_now()
        )

      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          dataclip: wiped_dataclip,
          state: :success,
          runs: [
            build(:run,
              dataclip: wiped_dataclip,
              starting_job: job_1,
              state: :success,
              steps: [
                build(:step,
                  job: job_1,
                  input_dataclip: nil,
                  output_dataclip: nil,
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success"
                ),
                build(:step,
                  job: job_2,
                  input_dataclip: nil,
                  output_dataclip: nil,
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success"
                )
              ]
            )
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_2.id, a: run.id, m: "expand"]}"
        )

      # user cannot rerun
      refute has_element?(view, "button", "Rerun from here")

      assert has_element?(view, "button:disabled", "Create New Work Order"),
             "create new workorder button is disabled"
    end

    test "selected dataclip viewer is updated correctly if dataclip is wiped and step completed",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1, _job_2 | _rest]} = workflow
         } do
      unique_val = "random" <> Ecto.UUID.generate()

      input_dataclip =
        insert(:dataclip,
          project: project,
          type: :saved_input,
          body: %{"foo" => unique_val}
        )

      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          dataclip: input_dataclip,
          state: :running,
          runs: [
            build(:run,
              dataclip: input_dataclip,
              starting_job: job_1,
              state: :started,
              steps: []
            )
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1.id, a: run.id, m: "expand"]}"
        )

      # dataclip body is displayed
      html = view |> element("#manual-job-#{job_1.id}") |> render()
      assert html =~ unique_val, "dataclip body is present"
      refute html =~ "data for this step has not been retained"

      # let's subscribe to events to make sure we're in sync with liveview
      Lightning.Runs.subscribe(run)

      # lets wipe the dataclip
      Lightning.Runs.wipe_dataclips(run)

      # start step without dataclip
      {:ok, %{id: step_id}} =
        Lightning.Runs.start_step(%{
          "run_id" => run.id,
          "job_id" => job_1.id,
          "step_id" => Ecto.UUID.generate()
        })

      assert_received %Lightning.Runs.Events.StepStarted{
        step: %{id: ^step_id}
      }

      # dataclip body is still present
      html = view |> element("#manual-job-#{job_1.id}") |> render()
      assert html =~ unique_val, "dataclip body is present when the step starts"

      # complete step without dataclip
      {:ok, _step} =
        Lightning.Runs.complete_step(%{
          step_id: step_id,
          reason: "success",
          run_id: run.id,
          project_id: project.id
        })

      assert_received %Lightning.Runs.Events.StepCompleted{
        step: %{id: ^step_id}
      }

      # make sure that the event is processed by liveview
      render(view)

      # dataclip body is nolonger present
      html = view |> element("#manual-job-#{job_1.id}") |> render()
      refute html =~ unique_val, "dataclip body has been removed"
      assert html =~ "data for this step has not been retained"
    end

    test "followed crashed run without steps renders the page correctly",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1 | _rest]} = workflow
         } do
      dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request
        )

      %{runs: [run]} =
        insert(:workorder,
          workflow: workflow,
          dataclip: dataclip,
          runs: [
            build(:run,
              dataclip: dataclip,
              starting_job: job_1,
              claimed_at: build(:timestamp),
              finished_at: build(:timestamp),
              started_at: nil,
              state: :crashed,
              error_type: "CompileError",
              steps: []
            )
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1.id, a: run.id, m: "expand"]}"
        )

      # user cannot rerun
      refute has_element?(view, "button", "Rerun from here")

      # user can create new work order
      assert has_element?(view, "button", "Create New Work Order")

      run_view = find_live_child(view, "run-viewer-#{run.id}")

      render_async(run_view)

      # input tab shows correct information
      html = run_view |> element("div[data-panel-hash='input']") |> render()
      assert html =~ "No input/output available. This step was never started."

      # output tab shows correct information
      html = run_view |> element("div[data-panel-hash='output']") |> render()
      assert html =~ "No input/output available. This step was never started."
    end

    test "viewer is updated correctly if manual run crashes",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1 | _rest]} = workflow
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1.id, m: "expand"]}"
        )

      # action button is rendered correctly
      refute has_element?(view, "button", "Rerun from here")
      refute has_element?(view, "button", "Processing")
      assert has_element?(view, "button", "Create New Work Order")

      # submit the manual run form
      view
      |> form("#manual_run_form", %{
        manual: %{body: "{}"}
      })
      |> render_submit()

      uri = view |> assert_patch() |> URI.parse()
      run_id = Plug.Conn.Query.decode(uri.query)["a"]
      run = Lightning.Repo.get!(Lightning.Run, run_id)

      # Get the Output/Logs View
      run_view = find_live_child(view, "run-viewer-#{run.id}")

      # action button is rendered correctly
      refute has_element?(view, "button", "Rerun from here")

      assert has_element?(view, "button:disabled", "Processing"),
             "currently processing"

      refute has_element?(view, "button", "Create New Work Order")

      render_async(run_view)
      # input tab shows correct information
      html = run_view |> element("div[data-panel-hash='input']") |> render()
      assert html =~ "Nothing yet"
      refute html =~ "No input/output available. This step was never started."

      # output tab shows correct information
      html = run_view |> element("div[data-panel-hash='output']") |> render()
      assert html =~ "Nothing yet"
      refute html =~ "No input/output available. This step was never started."

      # let's subscribe to events to make sure we're in sync with liveview
      Lightning.Runs.subscribe(run)

      # Let's claim the run
      run =
        run
        |> Ecto.Changeset.change(%{
          state: :claimed,
          claimed_at: DateTime.utc_now()
        })
        |> Lightning.Repo.update!()

      # lets crash the run
      {:ok, _run} =
        Lightning.Runs.complete_run(run, %{
          "error_message" => "Unexpected token (6:9)",
          "error_type" => "CompileError",
          "final_dataclip_id" => "",
          "state" => :crashed
        })

      assert_received %Lightning.Runs.Events.RunUpdated{
        run: %{id: ^run_id}
      }

      # make sure that the event is processed by liveview
      render(view)

      # action button is rendered correctly.
      refute has_element?(view, "button", "Rerun from here")
      refute has_element?(view, "button", "Processing"), "nolonger processing"
      assert has_element?(view, "button", "Create New Work Order")

      # make sure event is processed by the run viewer
      render_async(run_view)

      # input tab shows correct information
      html = run_view |> element("div[data-panel-hash='input']") |> render()
      refute html =~ "Nothing yet"
      assert html =~ "No input/output available. This step was never started."

      # output tab shows correct information
      html = run_view |> element("div[data-panel-hash='output']") |> render()
      refute html =~ "Nothing yet"
      assert html =~ "No input/output available. This step was never started."
    end
  end

  describe "Editor events" do
    test "can handle request_metadata event", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      project_credential =
        insert(:project_credential,
          project: project,
          credential:
            build(:credential,
              schema: "http",
              body: %{
                baseUrl: "http://localhost:4002",
                username: "test",
                password: "test"
              }
            )
        )

      job = workflow.jobs |> hd()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}"
        )

      assert has_element?(view, "#job-editor-pane-#{job.id}")

      assert view
             |> with_target("#job-editor-pane-#{job.id}")
             |> render_click("request_metadata", %{})

      assert_push_event(view, "metadata_ready", %{"error" => "no_credential"})

      view
      |> form("#workflow-form",
        workflow: %{
          jobs: %{
            "0" => %{
              "project_credential_id" => project_credential.id
            }
          }
        }
      )
      |> render_change()

      assert view
             |> with_target("#job-editor-pane-#{job.id}")
             |> render_click("request_metadata", %{})

      # set timeout to 60 secs because of CI
      assert_push_event(
        view,
        "metadata_ready",
        %{
          "error" => "no_metadata_function"
        },
        60000
      )
    end
  end
end
