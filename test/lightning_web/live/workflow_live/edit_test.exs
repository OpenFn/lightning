defmodule LightningWeb.WorkflowLive.EditTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Eventually
  import ExUnit.CaptureLog
  import Lightning.Factories
  import Lightning.JobsFixtures
  import Lightning.WorkflowLive.Helpers
  import Lightning.WorkflowsFixtures
  import Lightning.GithubHelpers
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Mox

  alias Lightning.Auditing.Audit
  alias Lightning.Helpers
  alias Lightning.Repo
  alias Lightning.Workflows
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias LightningWeb.CredentialLiveHelpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "New credential from project context " do
    setup %{project: project} do
      %{job: job} = workflow_job_fixture(project_id: project.id)
      workflow = Repo.get(Workflow, job.workflow_id)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      %{job: job, workflow: workflow, snapshot: snapshot}
    end

    test "open credential modal from the job inspector (edit_workflow)", %{
      conn: conn,
      project: project,
      job: job,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{job.workflow_id}?s=#{job.id}&v=#{workflow.lock_version}"
        )

      assert has_element?(view, "#job-pane-#{job.id}")

      assert has_element?(view, "#credential-schema-picker")
      view |> CredentialLiveHelpers.select_credential_type("http")
      view |> CredentialLiveHelpers.click_continue()

      refute has_element?(view, "#project_list")
    end

    test "create new credential from job inspector and update the job form", %{
      conn: conn,
      project: project,
      job: job,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{job.workflow_id}?s=#{job.id}&v=#{workflow.lock_version}"
        )

      view |> CredentialLiveHelpers.select_credential_type("raw")
      view |> CredentialLiveHelpers.click_continue()

      view
      |> form("#credential-form-new",
        credential: %{
          name: "newly created credential",
          body: Jason.encode!(%{"a" => 1})
        }
      )
      |> render_submit()

      refute has_element?(view, "#credential-form")

      assert view
             |> element(
               ~S{[name='workflow[jobs][0][project_credential_id]'] option[selected="selected"]}
             )
             |> render() =~ "newly created credential",
             "Should have the project credential selected"
    end
  end

  describe "new" do
    test "builds a new workflow", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Naively add a job via the editor (calling the push-change event)
      assert view
             |> push_patches_to_view([add_job_patch()])

      # The server responds with a patch with any further changes
      assert_reply(
        view,
        %{
          patches: [
            %{op: "add", path: "/jobs/0/project_credential_id", value: nil},
            %{
              op: "add",
              path: "/jobs/0/errors",
              value: %{
                "body" => ["Code editor cannot be empty."],
                "name" => ["Job name can't be blank."]
              }
            },
            %{op: "add", path: "/jobs/0/body", value: ""},
            %{
              op: "add",
              path: "/jobs/0/adaptor",
              value: "@openfn/language-common@latest"
            },
            %{
              op: "add",
              path: "/errors/jobs",
              value: [
                %{
                  "body" => ["Code editor cannot be empty."],
                  "name" => ["Job name can't be blank."]
                }
              ]
            }
          ]
        }
      )
    end

    @tag role: :editor
    test "creating a new workflow", %{conn: conn, project: project} do
      Mox.verify_on_exit!()

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?m=settings")

      assert view |> push_patches_to_view(initial_workflow_patchset(project))

      workflow_name = view |> get_workflow_params() |> Map.get("name")

      assert workflow_name == ""

      assert view |> element("#workflow_name") |> render() =~ workflow_name

      assert view |> save_is_disabled?()

      workflow_name = "My Workflow"
      view |> fill_workflow_name(workflow_name)

      assert view |> save_is_disabled?()

      {job, _, _} = view |> select_first_job()

      view |> fill_job_fields(job, %{name: "My Job"})

      refute view |> selected_adaptor_version_element(job) |> render() =~
               ~r(value="@openfn/[a-z-]+@latest"),
             "should not have @latest selected by default"

      view |> CredentialLiveHelpers.select_credential_type("dhis2")

      view |> CredentialLiveHelpers.click_continue()

      # Creating a new credential from the Job panel
      view
      |> CredentialLiveHelpers.fill_credential(%{
        name: "My Credential",
        body: %{username: "foo", password: "bar", hostUrl: "http://someurl"}
      })

      view |> CredentialLiveHelpers.click_save()

      assert view |> selected_credential(job) =~ "My Credential"

      # Editing the Jobs' body
      view |> click_edit(job)

      view |> change_editor_text("some body")

      # By default, workflows are disabled to ensure a controlled setup.
      # Here, we enable the workflow to test the :too_many_workflows limit action
      view
      |> element("#toggle-control-workflow")
      |> render_click()

      refute view |> save_is_disabled?()

      assert view |> has_pending_changes()

      # Try saving with the limitter
      error_msg = "Oopsie Doopsie! An error occured"

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        1,
        fn %{type: :activate_workflow}, _context ->
          {:error, :too_many_workflows, %{text: error_msg}}
        end
      )

      html = click_save(view)

      assert html =~ error_msg

      # let return ok with the limitter
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        1,
        fn %{type: :activate_workflow}, _context ->
          :ok
        end
      )

      # subscribe to workflow events
      Lightning.Workflows.subscribe(project.id)

      click_save(view)

      assert %{id: workflow_id} =
               workflow =
               Lightning.Repo.one(
                 from w in Workflow,
                   where:
                     w.project_id == ^project.id and w.name == ^workflow_name
               )

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow_id}?#{[m: "expand", s: job.id, v: workflow.lock_version]}"
      )

      assert render(view) =~ "Workflow saved"

      # workflow updated event is emitted
      assert_received %Lightning.Workflows.Events.WorkflowUpdated{
        workflow: %{id: ^workflow_id}
      }
    end

    @tag role: :editor
    test "auditing snapshot creation", %{
      conn: conn,
      project: project,
      user: %{id: user_id}
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?m=settings")

      assert view |> push_patches_to_view(initial_workflow_patchset(project))

      workflow_name = "My Workflow"
      view |> fill_workflow_name(workflow_name)

      {job, _, _} = view |> select_first_job()

      view |> fill_job_fields(job, %{name: "My Job"})

      view |> CredentialLiveHelpers.select_credential_type("dhis2")

      view |> CredentialLiveHelpers.click_continue()

      # Creating a new credential from the Job panel
      view
      |> CredentialLiveHelpers.fill_credential(%{
        name: "My Credential",
        body: %{username: "foo", password: "bar", hostUrl: "http://someurl"}
      })

      view |> CredentialLiveHelpers.click_save()

      # Editing the Jobs' body
      view |> click_edit(job)

      view |> change_editor_text("some body")

      click_save(view)

      assert %{id: workflow_id} =
               Lightning.Repo.one(
                 from w in Workflow,
                   where:
                     w.project_id == ^project.id and w.name == ^workflow_name
               )

      audit_query = from a in Audit, where: a.event == "snapshot_created"

      audit_event = Lightning.Repo.one(audit_query)

      assert %{
               actor_id: ^user_id,
               item_id: ^workflow_id,
               item_type: "workflow"
             } = audit_event
    end

    @tag role: :viewer
    test "viewers can't create new workflows", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new")
        |> follow_redirect(conn, ~p"/projects/#{project.id}/w")

      assert html =~ "You are not authorized to perform this action."
    end
  end

  describe "edit" do
    setup :create_workflow

    test "Editing tracks user presence", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      assert [] = Presence.list_presences_for(workflow)
      refute Presence.has_any_presence?(workflow)

      {:ok, _view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      user = Map.put(user, :password, nil)

      assert [%Presence{user: ^user}] = Presence.list_presences_for(workflow)
      assert Presence.has_any_presence?(workflow)
    end

    test "Switching trigger types doesn't erase webhook URL input content", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      select_trigger(view)

      trigger = List.first(workflow.triggers)
      webhook_url = url(LightningWeb.Endpoint, ~p"/i/#{trigger.id}")

      view
      |> form("#workflow-form", %{
        "workflow" => %{"triggers" => %{"0" => %{"type" => "cron"}}}
      })
      |> render_change()

      click_save(view)

      refute view |> has_element?("#webhookUrlInput[value='#{webhook_url}']")

      select_trigger(view)

      view
      |> form("#workflow-form", %{
        "workflow" => %{"triggers" => %{"0" => %{"type" => "webhook"}}}
      })
      |> render_change()

      click_save(view)

      assert view |> has_element?("#webhookUrlInput[value='#{webhook_url}']")
    end

    test "Switching between workflow versions maintains correct read-only and edit modes",
         %{
           conn: conn,
           project: project,
           snapshot: snapshot,
           workflow: workflow
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      assert snapshot.lock_version == workflow.lock_version

      assert view
             |> has_element?(
               "[id='canvas-workflow-version'][aria-label='This is the latest version of this workflow']",
               "latest"
             )

      refute view
             |> has_element?(
               "[id='version-switcher-canvas-#{workflow.id}][data-version='latest']"
             )

      view |> fill_workflow_name("#{workflow.name} v2")

      workflow.jobs
      |> Enum.with_index()
      |> Enum.each(fn {job, idx} ->
        view |> select_node(job, workflow.lock_version)

        refute view
               |> has_element?("[id='workflow_jobs_#{idx}_name'][disabled]")

        refute view |> has_element?("[id='adaptor-name'][disabled]")
        refute view |> has_element?("[id='adaptor-version'][disabled]")

        refute view
               |> has_element?(
                 "[id='workflow_jobs_#{idx}_project_credential_id'][disabled]"
               )

        view |> click_edit(job)

        assert view
               |> has_element?(
                 "[id='inspector-workflow-version'][aria-label='This is the latest version of this workflow']",
                 "latest"
               )

        refute view
               |> has_element?("[id='manual_run_form_dataclip_id'][disabled]")

        refute view
               |> has_element?(
                 "[id='job-editor-#{job.id}'][data-disabled='true']"
               )

        refute view
               |> has_element?("[id='version-switcher-inspector-#{job.id}]")

        refute view
               |> has_element?(
                 "[type='submit'][form='workflow-form'][disabled]",
                 "Save"
               )
      end)

      workflow.edges
      |> Enum.with_index()
      |> Enum.each(fn {edge, idx} ->
        view |> select_node(edge, workflow.lock_version)

        refute view
               |> has_element?(
                 "[id='workflow_edges_#{idx}_condition_type'][disabled]"
               )
      end)

      workflow.triggers
      |> Enum.with_index()
      |> Enum.each(fn {trigger, idx} ->
        view |> select_node(trigger, workflow.lock_version)

        refute view
               |> has_element?("[id='triggerType'][disabled]")

        refute view
               |> has_element?(
                 "[id='workflow_triggers_#{idx}_enabled'][disabled]"
               )
      end)

      job_1 = List.first(workflow.jobs)

      view |> select_node(job_1, workflow.lock_version)

      view
      |> form("#workflow-form", %{
        "workflow" => %{
          "jobs" => %{
            "0" => %{
              "name" => "#{job_1.name} v2"
            }
          }
        }
      })
      |> render_change()

      view
      |> form("#workflow-form")
      |> render_submit()

      workflow = Repo.reload!(workflow)

      assert snapshot.lock_version < workflow.lock_version

      version = String.slice(snapshot.id, 0..6)

      view
      |> element(
        "a[href='/projects/#{project.id}/w'][data-phx-link='redirect']",
        "Workflows"
      )
      |> render_click()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: snapshot.lock_version]}"
        )

      assert view
             |> has_element?(
               "[id='canvas-workflow-version'][aria-label='You are viewing a snapshot of this workflow that was taken on #{Helpers.format_date(snapshot.inserted_at)}']",
               version
             )

      assert view
             |> has_element?(
               "[id='version-switcher-button-#{workflow.id}']",
               "Switch to latest version"
             )

      snapshot.jobs
      |> Enum.with_index()
      |> Enum.each(fn {job, idx} ->
        view |> select_node(job, workflow.lock_version)

        assert view
               |> has_element?("[id='snapshot_jobs_#{idx}_name'][disabled]")

        assert view |> has_element?("[id='adaptor-name'][disabled]")
        assert view |> has_element?("[id='adaptor-version'][disabled]")

        assert view
               |> has_element?(
                 "[id='snapshot_jobs_#{idx}_project_credential_id'][disabled]"
               )

        view |> click_edit(job)

        assert view
               |> has_element?(
                 "[id='inspector-workflow-version'][aria-label='You are viewing a snapshot of this workflow that was taken on #{Helpers.format_date(snapshot.inserted_at)}']",
                 version
               )

        view
        |> has_element?("[id='manual_run_form_dataclip_id'][disabled]")

        assert view
               |> has_element?(
                 "[id='job-editor-#{job.id}'][data-disabled='true'][data-disabled-message=\"You can't edit while viewing a snapshot, switch to the latest version.\""
               )

        assert view
               |> has_element?("[id='version-switcher-toggle-#{job.id}]")

        assert view
               |> has_element?(
                 "[type='submit'][form='workflow-form'][disabled]",
                 "Save"
               )
      end)

      snapshot.edges
      |> Enum.with_index()
      |> Enum.each(fn {edge, idx} ->
        view |> select_node(edge, workflow.lock_version)

        assert view
               |> has_element?(
                 "[id='snapshot_edges_#{idx}_condition_type'][disabled]"
               )
      end)

      snapshot.triggers
      |> Enum.with_index()
      |> Enum.each(fn {trigger, idx} ->
        view |> select_node(trigger, workflow.lock_version)

        assert view
               |> has_element?("[id='triggerType'][disabled]")

        assert view
               |> has_element?(
                 "[id='snapshot_triggers_#{idx}_enabled'][disabled]"
               )
      end)

      last_job = List.last(snapshot.jobs)
      last_edge = List.last(snapshot.edges)

      assert force_event(view, :save) =~
               "Cannot save in snapshot mode, switch to the latest version."

      assert force_event(view, :delete_node, last_job) =~
               "Cannot delete a step in snapshot mode, switch to latest"

      view |> select_node(last_edge, snapshot.lock_version)

      assert force_event(view, :delete_edge, last_edge) =~
               "Cannot delete an edge in snapshot mode, switch to latest"

      assert force_event(view, :manual_run_submit, %{}) =~
               "Cannot run in snapshot mode, switch to latest."

      assert force_event(view, :rerun, nil, nil) =~
               "Cannot rerun in snapshot mode, switch to latest."

      assert view |> element("#edit-disabled-warning") |> render() =~
               "You cannot edit or run an old snapshot of a workflow"

      assert view
             |> element("#version-switcher-button-#{workflow.id}")
             |> has_element?()

      refute view |> element("[type='submit']", "Save") |> has_element?()

      view
      |> element("#version-switcher-button-#{workflow.id}")
      |> render_click()

      refute view |> has_element?("#edit-disabled-warning")

      refute render(view) =~
               "You cannot edit or run an old snapshot of a workflow"

      refute view
             |> element("#version-switcher-button-#{workflow.id}")
             |> has_element?()

      assert view |> element("[type='submit']", "Save") |> has_element?()
    end

    test "Creating an audit event on rerun", %{
      conn: conn,
      project: project,
      snapshot: snapshot,
      user: %{id: user_id},
      workflow: %{id: workflow_id} = workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      view |> fill_workflow_name("#{workflow.name} v2")

      job_1 = List.first(workflow.jobs)

      view |> select_node(job_1, workflow.lock_version)

      view
      |> form("#workflow-form", %{
        "workflow" => %{
          "jobs" => %{
            "0" => %{
              "name" => "#{job_1.name} v2"
            }
          }
        }
      })
      |> render_change()

      view
      |> form("#workflow-form")
      |> render_submit()

      workflow = Repo.reload!(workflow)

      view
      |> element(
        "a[href='/projects/#{project.id}/w'][data-phx-link='redirect']",
        "Workflows"
      )
      |> render_click()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: snapshot.lock_version]}"
        )

      last_edge = List.last(snapshot.edges)

      existing_audit_ids = Audit |> Repo.all() |> Enum.map(& &1.id)
      existing_snapshot_ids = Snapshot |> Repo.all() |> Enum.map(& &1.id)

      view |> select_node(last_edge, snapshot.lock_version)

      force_event(view, :manual_run_submit, %{})

      force_event(view, :rerun, nil, nil)

      snapshots_query =
        from s in Snapshot, where: s.id not in ^existing_snapshot_ids

      [%{id: latest_snapshot_id}] = Lightning.Repo.all(snapshots_query)

      audit_query =
        from a in Audit, where: a.id not in ^existing_audit_ids

      [audit] = Lightning.Repo.all(audit_query)

      assert %{
               event: "snapshot_created",
               actor_id: ^user_id,
               item_id: ^workflow_id,
               item_type: "workflow",
               changes: %{
                 after: %{"snapshot_id" => ^latest_snapshot_id}
               }
             } = audit
    end

    test "Inspector renders run thru their snapshots and allows switching to the latest versions for editing",
         %{
           conn: conn,
           project: project,
           snapshot: earliest_snapshot,
           user: user,
           workflow: workflow
         } do
      run_1 =
        insert(:run,
          work_order: build(:workorder, workflow: workflow),
          starting_trigger: build(:trigger),
          dataclip: build(:dataclip),
          finished_at: build(:timestamp),
          snapshot: earliest_snapshot,
          state: :started
        )

      jobs_attrs =
        workflow.jobs
        |> Enum.with_index()
        |> Enum.map(fn {job, idx} ->
          %{
            id: job.id,
            name: "job-number-#{idx}",
            body:
              ~s[fn(state => { console.log("job body number #{idx}"); return state; })]
          }
        end)

      {:ok, workflow} =
        Workflows.change_workflow(workflow, %{jobs: jobs_attrs})
        |> Workflows.save_workflow(user)

      latest_snapshot = Snapshot.get_current_for(workflow)

      run_2 =
        insert(:run,
          work_order: build(:workorder, workflow: workflow),
          starting_trigger: build(:trigger),
          dataclip: build(:dataclip),
          finished_at: build(:timestamp),
          snapshot: latest_snapshot,
          state: :started
        )

      job_1 = List.last(run_1.snapshot.jobs)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run_1, s: job_1, m: "expand", v: run_1.snapshot.lock_version]}"
        )

      run_1_version = String.slice(run_1.snapshot.id, 0..6)

      assert view
             |> has_element?(
               "[id='inspector-workflow-version'][aria-label='You are viewing a snapshot of this workflow that was taken on #{Helpers.format_date(run_1.snapshot.inserted_at)}']",
               run_1_version
             )

      assert view
             |> has_element?(
               "#job-editor-panel-panel-header-title",
               "Editor (read-only)"
             )

      assert view
             |> has_element?(
               "[id='job-editor-#{job_1.id}'][data-disabled='true'][data-source='#{job_1.body}'][data-disabled-message=\"You can't edit while viewing a snapshot, switch to the latest version.\"]"
             )

      assert view |> has_element?("[id='manual_run_form_dataclip_id'][disabled]")

      assert view |> has_element?("div", job_1.name)

      view |> element("#version-switcher-toggle-#{job_1.id}") |> render_click()

      job_2 = List.last(run_2.snapshot.jobs)

      assert view
             |> has_element?(
               "[id='inspector-workflow-version'][aria-label='This is the latest version of this workflow']",
               "latest"
             )

      assert view
             |> has_element?(
               "#job-editor-panel-panel-header-title",
               "Editor"
             )

      assert view
             |> has_element?(
               "[id='job-editor-#{job_1.id}'][data-disabled-message=''][data-disabled='false'][data-source='#{job_2.body}']"
             )

      refute view |> has_element?("[id='manual_run_form_dataclip_id'][disabled]")

      assert view |> has_element?("div", job_2.name)
    end

    test "Can't switch to the latest version from a deleted step", %{
      conn: conn,
      project: project,
      snapshot: snapshot,
      user: user,
      workflow: workflow
    } do
      run =
        insert(:run,
          work_order: build(:workorder, workflow: workflow),
          starting_trigger: build(:trigger),
          dataclip: build(:dataclip),
          finished_at: build(:timestamp),
          snapshot: snapshot,
          state: :started
        )

      jobs_attrs =
        workflow.jobs
        |> Enum.with_index()
        |> Enum.map(fn {job, idx} ->
          %{
            id: job.id,
            name: "job-number-#{idx}",
            body:
              ~s[fn(state => { console.log("job body number #{idx}"); return state; })]
          }
        end)

      {:ok, workflow} =
        Workflows.change_workflow(workflow, %{jobs: jobs_attrs})
        |> Workflows.save_workflow(user)

      latest_snapshot = Snapshot.get_current_for(workflow)

      insert(:run,
        work_order: build(:workorder, workflow: workflow),
        starting_trigger: build(:trigger),
        dataclip: build(:dataclip),
        finished_at: build(:timestamp),
        snapshot: latest_snapshot,
        state: :started
      )

      job_to_delete = workflow.jobs |> List.last() |> Repo.delete!()

      workflow = Repo.reload(workflow) |> Repo.preload(:jobs)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job_to_delete, m: "expand", v: run.snapshot.lock_version]}"
        )

      assert view
             |> has_element?(
               "[id='version-switcher-toggle-#{job_to_delete.id}'][disabled]"
             )

      assert view
             |> render_click("switch-version", %{"type" => "toggle"}) =~
               "Can&#39;t switch to the latest version, the job has been deleted from the workflow."
    end

    test "click on pencil icon activates workflow name edit mode", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      another_workflow =
        workflow_fixture(name: "A random workflow", project_id: project.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, m: "settings"]}"
        )

      assert view |> has_element?(~s(input[name="workflow[name]"]))

      assert view
             |> form("#workflow-form", %{"workflow" => %{"name" => ""}})
             |> render_change() =~ "can&#39;t be blank"

      html =
        view
        |> form("#workflow-form", %{
          "workflow" => %{"name" => another_workflow.name}
        })
        |> render_submit()

      assert html =~ "a workflow with this name already exists in this project."
      assert html =~ "Workflow could not be saved"

      assert view
             |> form("#workflow-form", %{
               "workflow" => %{"name" => "some new name"}
             })
             |> render_submit() =~ "Workflow saved"
    end

    test "using the settings panel", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      refute has_element?(view, "#workflow-settings-#{workflow.id}")

      view
      |> element("#toggle-settings")
      |> render_click()

      path = assert_patch(view)
      assert path == ~p"/projects/#{project.id}/w/#{workflow.id}?m=settings"

      assert has_element?(view, "#workflow-settings-#{workflow.id}")
      html = render(view)
      assert html =~ "Workflow settings"
      assert html =~ "Unlimited (up to max available)"

      assert view
             |> form("#workflow-form", %{"workflow" => %{"concurrency" => "0"}})
             |> render_change() =~ "must be greater than or equal to 1"

      assert view |> element("#workflow-form") |> render_submit() =~
               "Workflow could not be saved"

      assert view
             |> form("#workflow-form", %{"workflow" => %{"concurrency" => "1"}})
             |> render_change() =~ "No more than one run at a time"

      assert view
             |> form("#workflow-form", %{"workflow" => %{"concurrency" => "5"}})
             |> render_change() =~ "No more than 5 runs at a time"

      assert view |> element("#workflow-form") |> render_submit() =~
               "Workflow saved"

      assert assert_patch(view) =~
               ~p"/projects/#{project.id}/w/#{workflow.id}?m=settings"

      assert view
             |> form("#workflow-form", %{"workflow" => %{"concurrency" => ""}})
             |> render_change() =~ "Unlimited"

      view |> element("#toggle-settings") |> render()

      view
      |> element("#toggle-settings")
      |> render_click()

      refute has_element?(view, "#workflow-settings-#{workflow.id}")

      assert assert_patch(view) == ~p"/projects/#{project.id}/w/#{workflow.id}"

      # bring the settings panel back, so we can test that selecting something
      # else will close it
      view
      |> element("#toggle-settings")
      |> render_click()

      assert_patch(view)

      job = workflow.jobs |> Enum.at(1)

      view |> select_node(job)

      assert assert_patch(view) ==
               ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job.id}"

      refute has_element?(view, "#workflow-settings-#{workflow.id}"),
             "should not have settings panel present"

      # bring it back again to test the close button
      view
      |> element("#toggle-settings")
      |> render_click()

      refute has_element?(view, "#job-pane-#{job.id}"),
             "should not have job pane anymore"

      assert assert_patch(view) ==
               ~p"/projects/#{project.id}/w/#{workflow.id}?m=settings"

      view
      |> element("#close-panel")
      |> render_click()

      refute has_element?(view, "#workflow-settings-#{workflow.id}")

      assert assert_patch(view) == ~p"/projects/#{project.id}/w/#{workflow.id}"
    end

    test "toggling run log settings in the settings panel", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}"
          )

        view
        |> element("#toggle-settings")
        |> render_click()

        assert has_element?(
                 view,
                 "#toggle-workflow-logs-btn"
               )

        assert_raise ArgumentError,
                     ~r/cannot click element "#toggle-workflow-logs-btn" because it is disabled/,
                     fn ->
                       view
                       |> element("#toggle-workflow-logs-btn")
                       |> render_click()
                     end

        GenServer.stop(view.pid)
      end

      for {conn, _user} <- setup_project_users(conn, project, [:admin, :owner]) do
        workflow =
          workflow
          |> Repo.reload()
          |> Ecto.Changeset.change(%{enable_job_logs: true})
          |> Repo.update!()

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}"
          )

        view
        |> element("#toggle-settings")
        |> render_click()

        assert has_element?(
                 view,
                 "#toggle-workflow-logs-btn"
               )

        view
        |> form("#workflow-form")
        |> render_change(workflow: %{enable_job_logs: "false"})

        assert workflow.enable_job_logs == true

        # submit the form
        view |> element("#workflow-form") |> render_submit()

        assert assert_patch(view) =~
                 ~p"/projects/#{project.id}/w/#{workflow.id}?m=settings"

        assert Repo.reload(workflow).enable_job_logs == false

        GenServer.stop(view.pid)
      end
    end

    test "renders error message when a job has an empty body", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      job = workflow.jobs |> Enum.at(1)

      view |> select_node(job, workflow.lock_version)

      view |> click_edit(job)

      view |> change_editor_text("some body")

      refute view |> render() =~
               "Code editor cannot be empty."

      view |> change_editor_text("")

      assert view |> render() =~
               "Code editor cannot be empty."
    end

    test "allows editing job name", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      assert view |> page_title() =~ workflow.name

      view |> fill_workflow_name("")

      job_2 = workflow.jobs |> Enum.at(1)

      view |> select_node(job_2, workflow.lock_version)
      view |> fill_job_fields(job_2, %{name: ""})

      assert view |> job_form_has_error(job_2, "name", "can't be blank")
      assert view |> save_is_disabled?()

      new_job_name = "My Other Job"

      assert view |> fill_job_fields(job_2, %{name: new_job_name}) =~
               new_job_name

      assert view |> save_is_disabled?()
    end

    test "renders the job form correctly when local_adaptors_repo is NOT set", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      job_1 = hd(workflow.jobs)

      view |> select_node(job_1, workflow.lock_version)

      adaptor_name_label =
        view |> element("label[for='adaptor-name']") |> render()

      assert adaptor_name_label =~ "Adaptor"
      refute adaptor_name_label =~ "Adaptor (local)"

      # adapter version picker is available
      assert has_element?(view, "#adaptor-version")
    end

    @tag :tmp_dir
    test "renders the job form correctly when local_adaptors_repo is set", %{
      conn: conn,
      project: project,
      workflow: workflow,
      tmp_dir: tmp_dir
    } do
      Mox.stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repo: tmp_dir]
      end)

      expected_adaptors = ["foo", "bar", "baz"]

      Enum.each(expected_adaptors, fn adaptor ->
        [tmp_dir, "packages", adaptor] |> Path.join() |> File.mkdir_p!()
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      job_1 = hd(workflow.jobs)

      view |> select_node(job_1, workflow.lock_version)

      adaptor_name_label =
        view |> element("label[for='adaptor-name']") |> render()

      assert adaptor_name_label =~ "Adaptor (local)"

      # version picker is not present
      refute has_element?(view, "#adaptor-version")
    end

    test "Save button is disabled when workflow is deleted", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      workflow
      |> Ecto.Changeset.change(%{
        deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Lightning.Repo.update!()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      assert view |> page_title() =~ workflow.name

      assert view |> save_is_disabled?()

      # try changing the workflow name anyway
      assert render_click(view, "save", %{name: "updatename"}) =~
               "Oops! You cannot modify a deleted workflow"
    end

    test "opens edge Path form and saves the JS expression", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      form_html =
        view |> select_node(Enum.at(workflow.jobs, 0), workflow.lock_version)

      assert form_html =~ "Job Name"
      refute form_html =~ "Path"

      form_html =
        view |> select_node(Enum.at(workflow.edges, 0), workflow.lock_version)

      assert form_html =~ "Path"

      assert form_html =~ "Label"

      assert form_html =~
               ~S[<option selected="selected" value="always">Always</option><option value="js_expression">Matches a Javascript Expression</option></select>]

      edge_on_edit = Enum.at(workflow.edges, 1)
      form_html = view |> select_node(edge_on_edit, workflow.lock_version)

      assert form_html =~
               ~S[<option selected="selected" value="on_job_success">On Success</option>]

      form_html =
        view
        |> form("#workflow-form", %{
          "workflow" => %{
            "edges" => %{"1" => %{"condition_type" => "js_expression"}}
          }
        })
        |> render_change()

      assert form_html =~ "Label"

      assert form_html =~
               ~S[<option selected="selected" value="js_expression">Matches a Javascript Expression</option>]

      view
      |> form("#workflow-form", %{
        "workflow" => %{
          "edges" => %{
            "1" => %{
              "condition_label" => "My JS Expression",
              "condition_expression" => "state.data.field === 33"
            }
          }
        }
      })
      |> render_change()

      view
      |> form("#workflow-form")
      |> render_submit()

      assert Map.delete(Repo.reload!(edge_on_edit), :updated_at) ==
               Map.delete(
                 Map.merge(edge_on_edit, %{
                   condition_type: :js_expression,
                   condition_label: "My JS Expression",
                   condition_expression: "state.data.field === 33"
                 }),
                 :updated_at
               )
    end

    @tag role: :editor
    test "can delete a job", %{conn: conn, project: project, workflow: workflow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}"
        )

      [job_1, job_2] = workflow.jobs
      view |> select_node(job_1, workflow.lock_version)

      assert view |> delete_job_button_is_disabled?(job_1)

      # Test that the delete event doesn't work even if the button is disabled.
      assert view |> force_event(:delete_node, job_1) =~
               "Delete all descendant steps first."

      view |> select_node(job_2, workflow.lock_version)

      assert_patched(
        view,
        ~p"/projects/#{project}/w/#{workflow}?s=#{job_2}&v=#{workflow.lock_version}"
      )

      refute view |> delete_job_button_is_disabled?(job_2)

      view |> click_delete_job(job_2)

      assert_push_event(view, "patches-applied", %{
        patches: [
          %{op: "remove", path: "/jobs/1"},
          %{op: "remove", path: "/edges/1"}
        ]
      })
    end

    @tag role: :editor
    test "cannot delete an edge between a trigger and a job", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}"
        )

      [trigger_edge, other_edge] = workflow.edges

      assert view |> select_node(other_edge, workflow.lock_version) =~
               "Delete Path"

      refute view |> select_node(trigger_edge, workflow.lock_version) =~
               "Delete Path"

      assert view |> force_event(:delete_edge, trigger_edge) =~
               "You cannot remove the first edge in a workflow."
    end

    @tag role: :editor
    test "can delete an edge between two jobs", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}"
        )

      [_trigger_edge, other_edge] = workflow.edges

      assert view |> select_node(other_edge, workflow.lock_version) =~
               "Delete Path"

      view |> select_node(other_edge, workflow.lock_version)

      assert_patched(
        view,
        ~p"/projects/#{project}/w/#{workflow}?s=#{other_edge}&v=#{workflow.lock_version}"
      )

      view |> click_delete_edge(other_edge)

      assert_push_event(view, "patches-applied", %{
        patches: [
          %{op: "remove", path: "/edges/1"}
        ]
      })
    end

    @tag role: :viewer
    test "cannot delete edges", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}"
        )

      [_trigger_edge, other_edge] = workflow.edges

      assert view |> select_node(other_edge, workflow.lock_version) =~
               "Delete Path"

      view |> select_node(other_edge, workflow.lock_version)

      assert_patched(
        view,
        ~p"/projects/#{project}/w/#{workflow}?s=#{other_edge}&v=#{workflow.lock_version}"
      )

      assert view |> delete_edge_button_is_disabled?(other_edge)

      assert view |> force_event(:delete_edge, other_edge) =~
               "You are not authorized to delete edges."
    end

    @tag role: :editor
    test "can't delete the first step in a workflow", %{
      conn: conn,
      project: project
    } do
      trigger = build(:trigger, type: :webhook)

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          name: "First Job"
        )

      workflow =
        build(:workflow, project: project)
        |> with_job(job)
        |> with_trigger(trigger)
        |> with_edge({trigger, job})
        |> insert()
        |> with_snapshot()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}"
        )

      view |> select_node(job, workflow.lock_version)

      assert view |> delete_job_button_is_disabled?(job)

      assert view |> force_event(:delete_node, job) =~
               "You can&#39;t delete the first step in a workflow."
    end

    @tag role: :editor
    test "can delete a step that has already been ran", %{
      conn: conn,
      project: project
    } do
      trigger = build(:trigger, type: :webhook)

      [job_a, job_b] = insert_list(2, :job)

      workflow =
        build(:workflow)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> with_edge({job_a, job_b})
        |> insert()
        |> with_snapshot()

      insert(:step, job: job_b)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}"
        )

      view |> select_node(job_b, workflow.lock_version)

      assert_patched(
        view,
        ~p"/projects/#{project}/w/#{workflow}?s=#{job_b}&v=#{workflow.lock_version}"
      )

      refute view |> delete_job_button_is_disabled?(job_b)

      view |> click_delete_job(job_b)

      project_id = project.id

      assert_push_event(view, "patches-applied", %{
        patches: [
          %{value: ^project_id, path: "/project_id", op: "replace"},
          %{op: "remove", path: "/jobs/1"},
          %{op: "remove", path: "/edges/1"}
        ]
      })
    end

    @tag role: :editor
    test "can't delete any job that has downstream jobs",
         %{
           conn: conn,
           project: project
         } do
      trigger = build(:trigger, type: :webhook)

      [job_a, job_b, job_c] = build_list(3, :job)

      workflow =
        build(:workflow)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_job(job_c)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> with_edge({job_a, job_b})
        |> with_edge({job_b, job_c})
        |> insert()
        |> with_snapshot()

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?s=#{job_a}&v=#{workflow.lock_version}"
        )

      assert view |> delete_job_button_is_disabled?(job_a)

      assert html =~
               "You can&#39;t delete a step that other downstream steps depend on"

      assert view |> force_event(:delete_node, job_a) =~
               "Delete all descendant steps first"

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?s=#{job_b}&v=#{workflow.lock_version}"
        )

      assert view |> delete_job_button_is_disabled?(job_b)

      assert html =~
               "You can&#39;t delete a step that other downstream steps depend on"

      assert view |> force_event(:delete_node, job_a) =~
               "Delete all descendant steps first"
    end

    @tag role: :viewer
    test "viewers can't edit existing jobs", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      view |> select_node(workflow.triggers |> Enum.at(0), workflow.lock_version)

      assert view |> input_is_disabled?("[name='workflow[triggers][0][type]']")

      view |> select_node(workflow.edges |> Enum.at(0), workflow.lock_version)

      assert view
             |> input_is_disabled?("[name='workflow[edges][0][condition_type]']")

      assert view |> save_is_disabled?()
      job_1 = workflow.jobs |> Enum.at(0)

      view |> select_node(job_1, workflow.lock_version)

      assert view |> input_is_disabled?(job_1, "name")

      assert view |> input_is_disabled?("[name='adaptor_picker[adaptor_name]']")
      assert view |> input_is_disabled?(job_1, "adaptor")
      assert view |> input_is_disabled?(job_1, "project_credential_id")

      assert view |> delete_job_button_is_disabled?(job_1)

      # Test that the delete event doesn't work even if the button is disabled.
      assert view |> force_event(:delete_node, job_1) =~
               "You are not authorized to perform this action."

      assert view |> save_is_disabled?()

      view |> click_close_error_flash()

      assert view |> force_event(:save) =~
               "You are not authorized to perform this action."

      view |> click_close_error_flash()

      assert view |> force_event(:form_changed) =~
               "You are not authorized to perform this action."

      view |> click_close_error_flash()

      assert view |> force_event(:validate) =~
               "You are not authorized to perform this action."
    end

    test "can enable/disable any edge between two jobs", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      edge =
        Enum.find(workflow.edges, fn edge -> edge.source_job_id != nil end)

      assert edge.enabled

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{edge.id}&v=#{workflow.lock_version}"
        )

      idx = get_index_of_edge(view, edge)

      assert html =~ "Enabled"

      assert view
             |> element("#workflow_edges_#{idx}_enabled")
             |> has_element?()

      view
      |> form("#workflow-form", %{
        "workflow" => %{"edges" => %{to_string(idx) => %{"enabled" => false}}}
      })
      |> render_change()

      view
      |> form("#workflow-form")
      |> render_submit()

      edge = Repo.reload!(edge)

      refute edge.enabled

      refute view
             |> element("#workflow_edges_#{idx}_enabled[checked]")
             |> has_element?()
    end

    test "does not call the limiter when the trigger is not enabled", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      Mox.verify_on_exit!()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      # We expect zero calls
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        0,
        fn %{type: :activate_workflow}, _context ->
          {:error, :too_many_workflows, %{text: "some error message"}}
        end
      )

      job_2 = workflow.jobs |> Enum.at(1)

      view |> select_node(job_2, workflow.lock_version)

      new_job_name = "My Other Job"

      assert view |> fill_job_fields(job_2, %{name: new_job_name}) =~
               new_job_name

      click_save(view)

      assert Lightning.Repo.reload(job_2).name == new_job_name
    end

    test "calls the limiter when the trigger is enabled", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      Mox.verify_on_exit!()

      workflow.triggers
      |> hd()
      |> Ecto.Changeset.change(%{enabled: false})
      |> Lightning.Repo.update!()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      # We expect 1 call
      error_msg = "Oopsie Doopsie! An error occured"

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        1,
        fn %{type: :activate_workflow}, _context ->
          {:error, :too_many_workflows, %{text: error_msg}}
        end
      )

      select_trigger(view)

      view
      |> form("#workflow-form", %{
        "workflow" => %{"triggers" => %{"0" => %{"enabled" => true}}}
      })
      |> render_change()

      html = click_save(view)

      assert html =~ error_msg
    end

    test "workflows are disabled by default", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user: user, role: :editor}])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/new?m=settings")

      push_patches_to_view(view, initial_workflow_patchset(project))

      fill_workflow_name(view, "My Workflow")

      {job, _, _} = select_first_job(view)

      fill_job_fields(view, job, %{name: "My Job"})

      click_edit(view, job)

      change_editor_text(view, "some body")

      html = click_save(view)

      assert html =~
               "Workflow saved successfully. Remember to enable your workflow to run it automatically."

      refute Workflows.get_workflows_for(project)
             |> List.first()
             |> Map.get(:triggers)
             |> List.first()
             |> Map.get(:enabled)
    end

    test "when workflow is enabled, reminder flash message is not displayed for the first save",
         %{
           conn: conn,
           user: user
         } do
      project = insert(:project, project_users: [%{user: user, role: :editor}])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/new?m=settings")

      push_patches_to_view(view, initial_workflow_patchset(project))

      fill_workflow_name(view, "My Workflow")

      {job, _, _} = select_first_job(view)

      fill_job_fields(view, job, %{name: "My Job"})

      click_edit(view, job)

      change_editor_text(view, "some body")

      view
      |> element("#toggle-control-workflow")
      |> render_click()

      html = click_save(view)

      refute html =~
               "Workflow saved successfully. Remember to enable your workflow to run it automatically."

      assert html =~
               "Workflow saved successfully."

      assert Workflows.get_workflows_for(project)
             |> List.first()
             |> Map.get(:triggers)
             |> List.first()
             |> Map.get(:enabled)
    end

    test "clicking on the toggle disables all the triggers of a workflow", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      assert workflow.triggers |> Enum.all?(& &1.enabled)

      view
      |> element("#toggle-control-workflow")
      |> render_click()

      click_save(view)

      workflow = Workflows.get_workflow(workflow.id, include: [:triggers])

      refute workflow.triggers |> Enum.any?(& &1.enabled)
    end

    test "workflow can still be disabled / enabled from the trigger form", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      assert workflow.triggers |> Enum.all?(& &1.enabled)

      select_trigger(view)

      view
      |> form("#workflow-form", %{
        "workflow" => %{"triggers" => %{"0" => %{"enabled" => "false"}}}
      })
      |> render_change()

      click_save(view)

      workflow = Workflows.get_workflow(workflow.id, include: [:triggers])

      refute workflow.triggers |> Enum.any?(& &1.enabled)
    end

    test "workflow state toggle tooltip messages vary by trigger type", %{
      conn: conn,
      project: project
    } do
      cron_trigger = build(:trigger, type: :cron, enabled: false)
      webhook_trigger = build(:trigger, type: :webhook, enabled: true)

      job_1 = build(:job)
      job_2 = build(:job)

      cron_workflow =
        build(:workflow)
        |> with_job(job_1)
        |> with_trigger(cron_trigger)
        |> with_edge({cron_trigger, job_1})
        |> insert()

      webhook_workflow =
        build(:workflow)
        |> with_job(job_2)
        |> with_trigger(webhook_trigger)
        |> with_edge({webhook_trigger, job_2})
        |> insert()

      Lightning.Workflows.Snapshot.create(cron_workflow)

      Lightning.Workflows.Snapshot.create(webhook_workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{cron_workflow.id}"
        )

      assert view
             |> has_element?(
               "#toggle-container-workflow[aria-label='This workflow is inactive (manual runs only)']"
             )

      view
      |> element("#toggle-control-workflow")
      |> render_click()

      assert view
             |> has_element?(
               "#toggle-container-workflow[aria-label='This workflow is active (cron trigger enabled)']"
             )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{webhook_workflow.id}"
        )

      assert view
             |> has_element?(
               "#toggle-container-workflow[aria-label='This workflow is active (webhook trigger enabled)']"
             )
    end

    test "manual run form body remains unchanged even after save workflow form is submitted",
         %{conn: conn, project: project, test: test} do
      %{jobs: [job_1, job_2 | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1, m: "expand"]}"
        )

      body = Jason.encode!(%{test: test})

      body_part = to_string(test)

      refute view |> element("#manual_run_form") |> render() =~ body_part

      assert view
             |> form("#manual_run_form")
             |> render_change(manual: %{body: body}) =~ body_part

      # submit workflow form
      view |> form("#workflow-form") |> render_submit()

      workflow = Lightning.Repo.reload(workflow)

      assert_patched(
        view,
        ~p"/projects/#{project}/w/#{workflow}?#{[m: "expand", s: job_1.id, v: workflow.lock_version]}"
      )

      # manual run form still has the body
      assert view |> element("#manual_run_form") |> render() =~ body_part

      # select another job
      select_node(view, %{id: job_2.id})
      click_edit(view, %{id: job_2.id})

      # manual run form body is cleared
      refute view |> element("#manual_run_form") |> render() =~ body_part
    end
  end

  describe "Tracking Workflow editor metrics" do
    setup :create_workflow

    setup context do
      Mox.stub(Lightning.MockConfig, :ui_metrics_tracking_enabled?, fn ->
        true
      end)

      current_log_level = Logger.level()
      Logger.configure(level: :info)

      on_exit(fn ->
        Logger.configure(level: current_log_level)
      end)

      context
      |> Map.merge(%{
        metrics: [
          %{
            "event" => "foo-bar-event",
            "start" => 1_737_635_739_914,
            "end" => 1_737_635_808_890
          }
        ]
      })
    end

    test "logs the metrics", %{
      conn: conn,
      metrics: metrics,
      project: project,
      workflow: %{id: workflow_id} = workflow
    } do
      assert [] = Presence.list_presences_for(workflow)
      refute Presence.has_any_presence?(workflow)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      fun = fn ->
        view
        |> editor_element()
        |> render_hook("workflow_editor_metrics_report", %{"metrics" => metrics})
      end

      assert capture_log(fun) =~ ~r/foo-bar-event/
      assert capture_log(fun) =~ ~r/#{workflow_id}/
    end
  end

  describe "Save and Sync to Github" do
    setup :verify_on_exit!
    setup :create_workflow

    setup %{project: project} do
      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      %{repo_connection: repo_connection}
    end

    @tag role: :editor
    test "is not available when project isn't connected to github", %{
      conn: conn,
      project: project,
      workflow: workflow,
      repo_connection: repo_connection
    } do
      Repo.delete!(repo_connection)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      refute view |> has_element?("button[phx-click='toggle_github_sync_modal']")
    end

    @tag role: :editor
    test "can be done when creating a new workflow", %{
      conn: conn,
      project: project,
      repo_connection: repo_connection
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?m=settings")

      assert view |> push_patches_to_view(initial_workflow_patchset(project))

      workflow_name = "My Workflow"
      view |> fill_workflow_name(workflow_name)

      assert view |> save_is_disabled?()

      {job, _, _} = view |> select_first_job()

      view |> fill_job_fields(job, %{name: "My Job"})

      # Editing the Jobs' body
      view |> click_edit(job)

      view |> change_editor_text("some body")

      refute view |> save_is_disabled?()

      assert view |> has_pending_changes()

      # let return ok with the limitter
      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context ->
          :ok
        end
      )

      # button to sync to github exists
      assert view |> has_element?("button[phx-click='toggle_github_sync_modal']")

      # verify connection
      repo_name = repo_connection.repo
      branch_name = repo_connection.branch
      installation_id = repo_connection.github_installation_id

      expected_default_branch = "main"

      expected_deploy_yml_path =
        ".github/workflows/openfn-#{repo_connection.project_id}-deploy.yml"

      expected_config_json_path =
        "openfn-#{repo_connection.project_id}-config.json"

      expected_secret_name =
        "OPENFN_#{String.replace(repo_connection.project_id, "-", "_")}_API_KEY"

      expect(Lightning.Tesla.Mock, :call, 6, fn
        # get installation access token.
        %{
          url:
            "https://api.github.com/app/installations/" <>
                ^installation_id <> "/access_tokens"
        },
        _opts ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # get repo content
        %{url: "https://api.github.com/repos/" <> ^repo_name}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"default_branch" => expected_default_branch}
           }}

        # check if pull yml exists in the default branch
        %{
          method: :get,
          query: [{:ref, "heads/" <> ^expected_default_branch}],
          url:
            "https://api.github.com/repos/" <>
                ^repo_name <> "/contents/.github/workflows/openfn-pull.yml"
        },
        _opts ->
          {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

        # check if deploy yml exists in the target branch
        %{
          method: :get,
          query: [{:ref, "heads/" <> ^branch_name}],
          url:
            "https://api.github.com/repos/" <>
                ^repo_name <> "/contents/" <> ^expected_deploy_yml_path
        },
        _opts ->
          {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

        # check if config.json exists in the target branch
        %{
          method: :get,
          query: [{:ref, "heads/" <> ^branch_name}],
          url:
            "https://api.github.com/repos/" <>
                ^repo_name <> "/contents/" <> ^expected_config_json_path
        },
        _opts ->
          {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

        # check if api key secret exists
        %{
          method: :get,
          url:
            "https://api.github.com/repos/" <>
                ^repo_name <> "/actions/secrets/" <> ^expected_secret_name
        },
        _opts ->
          {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      # click to open the github sync modal
      refute has_element?(view, "#github-sync-modal")
      render_click(view, "toggle_github_sync_modal")
      assert has_element?(view, "#github-sync-modal")
      assert render_async(view) =~ "Save and sync changes to GitHub"

      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)
      expect_create_workflow_dispatch(repo_connection.repo, "openfn-pull.yml")

      # submit form
      view
      |> form("#workflow-form")
      |> render_submit(%{"github-sync" => %{"commit_message" => "some message"}})

      assert workflow =
               Lightning.Repo.one(
                 from w in Workflow,
                   where:
                     w.project_id == ^project.id and w.name == ^workflow_name
               )

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[m: "expand", s: job.id, v: workflow.lock_version]}"
      )

      assert render(view) =~ "Workflow saved and synced to GitHub successfully."
      refute has_element?(view, "#github-sync-modal")
    end

    test "does not close the github modal when Github sync fails", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      assert view |> page_title() =~ workflow.name

      job_2 = workflow.jobs |> Enum.at(1)

      view |> select_node(job_2, workflow.lock_version)

      new_job_name = "My Other Job"

      assert view |> fill_job_fields(job_2, %{name: new_job_name}) =~
               new_job_name

      refute view |> save_is_disabled?()

      # let return ok with the limitter
      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context ->
          :ok
        end
      )

      # return error for Github
      stub(Lightning.Tesla.Mock, :call, fn
        %{url: "https://api.github.com/app/installations" <> _rest}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 404,
             body: %{"error" => "some-error"}
           }}

        %{url: "https://api.github.com/" <> _rest}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 400,
             body: %{"error" => "some-error"}
           }}
      end)

      # click to open the github sync modal
      refute has_element?(view, "#github-sync-modal")
      render_click(view, "toggle_github_sync_modal")
      assert has_element?(view, "#github-sync-modal")

      # submit form
      view
      |> form("#workflow-form")
      |> render_submit(%{"github-sync" => %{"commit_message" => "some message"}})

      workflow = Repo.reload!(workflow)

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: job_2.id, v: workflow.lock_version]}"
      )

      assert render(view) =~
               "Workflow saved but not synced to GitHub. Check the project GitHub connection settings"

      # modal is still present
      assert has_element?(view, "#github-sync-modal")
    end

    test "save and sync button on the modal is disabled when verification is still going on",
         %{
           conn: conn,
           project: project,
           workflow: workflow
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}"
        )

      assert view |> page_title() =~ workflow.name

      job_2 = workflow.jobs |> Enum.at(1)

      view |> select_node(job_2, workflow.lock_version)

      new_job_name = "My Other Job"

      assert view |> fill_job_fields(job_2, %{name: new_job_name}) =~
               new_job_name

      refute view |> save_is_disabled?()

      # let return ok with the limitter
      stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context ->
          :ok
        end
      )

      stub(Lightning.Tesla.Mock, :call, fn
        %{url: "https://api.github.com/app/installations" <> _rest}, _opts ->
          # sleep to block the async task
          Process.sleep(5000)

          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}
      end)

      # click to open the github sync modal
      refute has_element?(view, "#github-sync-modal")
      render_click(view, "toggle_github_sync_modal")
      assert has_element?(view, "#github-sync-modal")

      assert view
             |> element("button#submit-btn-github-sync-modal")
             |> render() =~ "disabled=\"disabled\""
    end
  end

  describe "AI Assistant:" do
    setup :create_workflow

    test "non openfn.org users can access the AI Assistant", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      # user's email is not from @openfn.org
      refute String.match?(user.email, ~r/@openfn\.org/i)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      html = view |> element("#aichat-#{job_1.id}") |> render()
      assert html =~ "Get started with the AI Assistant"
    end

    @tag email: "user@openfn.org"
    test "correct information is displayed when the assistant is not configured",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1 | _]} = workflow
         } do
      # when not configured properly
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> nil
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)
      refute has_element?(view, "#aichat-#{job_1.id}")

      assert render(view) =~
               "AI Assistant has not been configured for your instance"

      # when configured properly
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)
      assert has_element?(view, "#aichat-#{job_1.id}")

      refute render(view) =~
               "AI Assistant has not been configured for your instance"
    end

    @tag email: "user@openfn.org"
    test "disclaimer ui is displayed when user has not read it", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      # when disclaimer hasn't been read and no session exists
      refute user.preferences["ai_assistant.disclaimer_read_at"]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      html = view |> element("#aichat-#{job_1.id}") |> render()
      assert html =~ "Get started with the AI Assistant"
      refute has_element?(view, "#ai-assistant-form")

      # let's try clicking the get started button
      view |> element("#get-started-with-ai-btn") |> render_click()
      html = view |> element("#aichat-#{job_1.id}") |> render()
      refute html =~ "Get started with the AI Assistant"
      assert has_element?(view, "#ai-assistant-form")

      assert Lightning.Repo.reload(user).preferences[
               "ai_assistant.disclaimer_read_at"
             ]
    end

    @tag email: "user@openfn.org"
    test "disclaimer ui is displayed when user read it more than 24 hours ago",
         %{
           conn: conn,
           project: project,
           user: user,
           workflow: %{jobs: [job_1 | _]} = workflow
         } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      date = DateTime.utc_now() |> DateTime.add(-24, :hour) |> DateTime.to_unix()

      skip_disclaimer(user, date)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      html = view |> element("#aichat-#{job_1.id}") |> render()
      assert html =~ "Get started with the AI Assistant"
      refute has_element?(view, "#ai-assistant-form")
    end

    @tag email: "user@openfn.org"
    test "disclaimer ui is NOT displayed when user read it less than 24 hours ago",
         %{
           conn: conn,
           project: project,
           user: user,
           workflow: %{jobs: [job_1 | _]} = workflow
         } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      html = view |> element("#aichat-#{job_1.id}") |> render()
      refute html =~ "Get started with the AI Assistant"
      assert has_element?(view, "#ai-assistant-form")
    end

    @tag email: "user@openfn.org"
    test "authorized users can send a message", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [%{"role" => "assistant", "content" => "Hello!"}]
               }
             }}
        end
      )

      [:owner, :admin, :editor]
      |> Enum.map(fn role ->
        timestamp = DateTime.utc_now() |> DateTime.to_unix()

        user =
          insert(:user,
            email: "email-#{Enum.random(1..1_000)}@testemail.org",
            preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
          )

        insert(:project_user, project: project, user: user, role: role)

        user
      end)
      |> Enum.each(fn user ->
        conn = log_in_user(conn, user)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
          )

        render_async(view)

        assert view
               |> form("#ai-assistant-form")
               |> has_element?()

        input_element = element(view, "#ai-assistant-form textarea")
        submit_btn = element(view, "#ai-assistant-form-submit-btn")

        assert has_element?(input_element)
        refute render(input_element) =~ "disabled=\"disabled\""
        assert has_element?(submit_btn)
        refute render(submit_btn) =~ "disabled=\"disabled\""

        # try submitting a message
        html =
          view
          |> form("#ai-assistant-form")
          |> render_submit(%{content: "Hello"})

        refute html =~ "You are not authorized to use the Ai Assistant"

        assert_patch(view)
      end)

      [:viewer]
      |> Enum.map(fn role ->
        timestamp = DateTime.utc_now() |> DateTime.to_unix()

        user =
          insert(:user,
            email: "email-#{Enum.random(1..1_000)}@openfn.org",
            preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
          )

        insert(:project_user, project: project, user: user, role: role)

        user
      end)
      |> Enum.each(fn user ->
        conn = log_in_user(conn, user)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
          )

        render_async(view)

        assert view
               |> form("#ai-assistant-form")
               |> has_element?()

        input_element = element(view, "#ai-assistant-form textarea")
        submit_btn = element(view, "#ai-assistant-form-submit-btn")

        assert has_element?(input_element)
        assert render(input_element) =~ "disabled=\"disabled\""
        assert has_element?(submit_btn)
        assert render(submit_btn) =~ "disabled=\"disabled\""

        # try submitting a message
        html =
          view
          |> form("#ai-assistant-form")
          |> render_submit(%{content: "Hello"})

        assert html =~ "You are not authorized to use the Ai Assistant"
      end)
    end

    @tag email: "user@openfn.org"
    test "submit btn is disabled in case the job isnt saved yet", %{
      conn: conn,
      project: project,
      user: user,
      workflow: workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      # add job to ui
      job_id = Ecto.UUID.generate()
      push_patches_to_view(view, [add_job_patch("new job", job_id)])

      # open inspector
      select_node(view, %{id: job_id})
      view |> element("a#open-inspector-#{job_id}") |> render_click()

      render_async(view)

      assert view
             |> form("#ai-assistant-form")
             |> has_element?()

      input_element = element(view, "#ai-assistant-form textarea")
      submit_btn = element(view, "#ai-assistant-form-submit-btn")

      assert has_element?(input_element)
      assert render(input_element) =~ "disabled=\"disabled\""
      assert has_element?(submit_btn)
      assert render(submit_btn) =~ "disabled=\"disabled\""

      assert has_element?(view, "#ai-assistant-form-submit-btn-tooltip")

      assert view |> element("#ai-assistant-form-submit-btn-tooltip") |> render() =~
               "Save the job first in order to use the AI Assistant"
    end

    @tag email: "user@openfn.org"
    test "form accepts phx-change", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      # click the get started button
      view |> element("#get-started-with-ai-btn") |> render_click()

      # change form
      random_text = "Ping12345678"

      html =
        view
        |> form("#ai-assistant-form")
        |> render_change(%{content: random_text})

      assert html =~ random_text
    end

    @tag email: "user@openfn.org"
    test "users can start a new session", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow,
      test: test
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            # delay the response to simulate a long running request
            # I'm doing this to test the pending assistant resp message
            test |> to_string() |> Lightning.subscribe()

            receive do
              :return_resp ->
                {:ok,
                 %Tesla.Env{
                   status: 200,
                   body: %{
                     "history" => [
                       %{"role" => "user", "content" => "Ping"},
                       %{"role" => "assistant", "content" => "Pong"}
                     ]
                   }
                 }}
            end
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      # click the get started button
      view |> element("#get-started-with-ai-btn") |> render_click()

      # submit a message
      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert_patch(view)

      # pending message is shown
      assert has_element?(view, "#assistant-pending-message")
      refute render(view) =~ "Pong"

      # return the response
      test |> to_string() |> Lightning.broadcast(:return_resp)
      html = render_async(view)

      # pending message is not shown
      refute has_element?(view, "#assistant-pending-message")
      assert html =~ "Pong"
    end

    @tag email: "user@openfn.org"
    test "users can resume a session", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      expected_question = "Can you help me with this?"
      expected_answer = "No, I am a robot"

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "user", "content" => "Ping"},
                   %{"role" => "assistant", "content" => "Pong"},
                   %{"role" => "user", "content" => expected_question},
                   %{"role" => "assistant", "content" => expected_answer}
                 ]
               }
             }}
        end
      )

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "Ping", user: user},
            %{role: :assistant, content: "Pong"}
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      refute render_async(view) =~ session.title

      view |> element("#get-started-with-ai-btn") |> render_click()

      assert render_async(view) =~ session.title

      # click the link to open the session
      view |> element("#session-#{session.id}") |> render_click()

      assert_patch(view)

      # submit a message
      html =
        view
        |> form("#ai-assistant-form")
        |> render_submit(%{content: expected_question})

      # answer is not yet shown
      refute html =~ expected_answer

      html = render_async(view)

      # answer is now displayed
      assert html =~ expected_answer
    end

    @tag email: "user@openfn.org"
    test "an error is displayed incase the assistant does not return 200", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok, %Tesla.Env{status: 400}}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      # click the get started button
      view |> element("#get-started-with-ai-btn") |> render_click()

      # submit a message
      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert_patch(view)

      render_async(view)

      # pending message is not shown
      assert has_element?(view, "#assistant-failed-message")

      assert view |> element("#assistant-failed-message") |> render() =~
               "Oops! Something went wrong. Please try again."
    end

    @tag email: "user@openfn.org"
    test "an error is displayed incase the assistant query process crashes", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            raise "oops"
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      # click the get started button
      view |> element("#get-started-with-ai-btn") |> render_click()

      # submit a message
      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert_patch(view)

      render_async(view)

      # pending message is not shown
      assert has_element?(view, "#assistant-failed-message")

      assert view |> element("#assistant-failed-message") |> render() =~
               "Oops! Something went wrong. Please try again."
    end

    @tag email: "user@openfn.org"
    test "shows a flash error when limit has reached", %{
      conn: conn,
      project: %{id: project_id} = project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001/health_check"
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      error_message = "You have reached your quota of AI queries"

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn %{
                                                                          type:
                                                                            :ai_usage
                                                                        },
                                                                        %{
                                                                          project_id:
                                                                            ^project_id
                                                                        } ->
        {:error, :exceeds_limit,
         %Lightning.Extensions.Message{text: error_message}}
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      # click the get started button
      view |> element("#get-started-with-ai-btn") |> render_click()

      assert has_element?(view, "#ai-assistant-error", error_message)
      assert render(view) =~ "aria-label=\"#{error_message}\""

      # submiting a message shows the flash
      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert has_element?(view, "#ai-assistant-error", error_message)
    end

    @tag email: "user@openfn.org"
    test "displays apollo server error messages", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      error_message = "Server is temporarily unavailable"

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 503,
               body: %{
                 "code" => 503,
                 "message" => error_message
               }
             }}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)
      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert_patch(view)
      render_async(view)

      assert view |> element("#assistant-failed-message") |> render() =~
               error_message
    end

    @tag email: "user@openfn.org"
    test "handles timeout errors from Apollo", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:error, :timeout}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert_patch(view)
      render_async(view)

      assert view |> element("#assistant-failed-message") |> render() =~
               "Request timed out. Please try again."
    end

    @tag email: "user@openfn.org"
    test "handles connection refused errors from Apollo", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:error, :econnrefused}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)
      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert_patch(view)
      render_async(view)

      assert view |> element("#assistant-failed-message") |> render() =~
               "Unable to reach the AI server. Please try again later."
    end

    @tag email: "user@openfn.org"
    test "handles unexpected errors from Apollo", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:error, :unknown_error}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)
      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: "Ping"})

      assert_patch(view)
      render_async(view)

      assert view |> element("#assistant-failed-message") |> render() =~
               "Oops! Something went wrong. Please try again."
    end

    @tag email: "user@openfn.org"
    test "users can sort chat sessions", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      older_session =
        insert(:chat_session,
          user: user,
          job: job_1,
          updated_at: ~N[2024-01-01 10:00:00],
          title: "January Session",
          messages: [
            %{role: :user, content: "First message", user: user},
            %{role: :assistant, content: "First response"}
          ]
        )

      newer_session =
        insert(:chat_session,
          user: user,
          job: job_1,
          updated_at: ~N[2024-02-01 10:00:00],
          title: "February Session",
          messages: [
            %{role: :user, content: "Second message", user: user},
            %{role: :assistant, content: "Second response"}
          ]
        )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      html = render(view)
      assert html =~ "Latest"

      links =
        Floki.find(
          Floki.parse_document!(html),
          "a[id^='session-']"
        )

      assert length(links) == 2
      [first_link, second_link] = links

      assert first_link |> Floki.attribute("id") == [
               "session-#{newer_session.id}"
             ]

      assert second_link |> Floki.attribute("id") == [
               "session-#{older_session.id}"
             ]

      view |> element("button[phx-click='toggle_sort']") |> render_click()
      html = render(view)

      links =
        Floki.find(
          Floki.parse_document!(html),
          "a[id^='session-']"
        )

      assert length(links) == 2
      [first_link, second_link] = links

      assert first_link |> Floki.attribute("id") == [
               "session-#{older_session.id}"
             ]

      assert second_link |> Floki.attribute("id") == [
               "session-#{newer_session.id}"
             ]

      view |> element("button[phx-click='toggle_sort']") |> render_click()
      html = render(view)

      links =
        Floki.find(
          Floki.parse_document!(html),
          "a[id^='session-']"
        )

      assert length(links) == 2
      [first_link, second_link] = links

      assert first_link |> Floki.attribute("id") == [
               "session-#{newer_session.id}"
             ]

      assert second_link |> Floki.attribute("id") == [
               "session-#{older_session.id}"
             ]
    end

    @tag email: "user@openfn.org"
    test "input field is cleared after sending a message", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "assistant", "content" => "Response!"}
                 ]
               }
             }}
        end
      )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      assert view
             |> form("#ai-assistant-form")
             |> has_element?()

      input_element = element(view, "#ai-assistant-form textarea")

      assert has_element?(input_element)

      message = "Hello, AI Assistant!"

      view
      |> form("#ai-assistant-form")
      |> render_submit(%{content: message})

      render_async(view)

      refute render(input_element) =~ message
    end

    @tag email: "user@openfn.org"
    test "users can retry failed messages", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok, %Tesla.Env{status: 500}}
      end)

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "Hello", status: :error, user: user}
          ]
        )

      timestamp = DateTime.utc_now() |> DateTime.to_unix()

      Ecto.Changeset.change(user, %{
        preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
      })
      |> Lightning.Repo.update!()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand", chat: session.id]}"
        )

      render_async(view)

      assert has_element?(
               view,
               "#retry-message-#{List.first(session.messages).id}"
             )

      # can't cancel first message of session
      refute has_element?(
               view,
               "#cancel-message-#{List.first(session.messages).id}"
             )

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "user", "content" => "Hello"},
                 %{"role" => "assistant", "content" => "Hi there!"}
               ]
             }
           }}
      end)

      view
      |> element("#retry-message-#{List.first(session.messages).id}")
      |> render_click()

      html = render_async(view)

      assert html =~ "Hi there!"

      refute has_element?(view, "#assistant-failed-message")
    end

    @tag email: "user@openfn.org"
    test "cancel buttons are available until only one message remains", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "First message", status: :error, user: user},
            %{role: :assistant, content: "First response"},
            %{
              role: :user,
              content: "Second message",
              status: :error,
              user: user
            },
            %{role: :assistant, content: "Second response"},
            %{role: :user, content: "Third message", status: :error, user: user}
          ]
        )

      timestamp = DateTime.utc_now() |> DateTime.to_unix()

      Ecto.Changeset.change(user, %{
        preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
      })
      |> Lightning.Repo.update!()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand", chat: session.id]}"
        )

      render_async(view)

      failed_messages = Enum.filter(session.messages, &(&1.status == :error))

      # Initially, all failed messages should have both retry and cancel buttons
      Enum.each(failed_messages, fn message ->
        assert has_element?(view, "#retry-message-#{message.id}")
        assert has_element?(view, "#cancel-message-#{message.id}")
      end)

      # Cancel messages one by one until only one remains
      Enum.take(failed_messages, length(failed_messages) - 1)
      |> Enum.each(fn message ->
        view
        |> element("#cancel-message-#{message.id}")
        |> render_click()

        refute has_element?(view, "#retry-message-#{message.id}")
        refute has_element?(view, "#cancel-message-#{message.id}")

        updated_session = Lightning.AiAssistant.get_session!(session.id)

        refute Enum.any?(updated_session.messages, &(&1.id == message.id))
      end)

      # After cancelling all messages except one, get the current session state
      updated_session = Lightning.AiAssistant.get_session!(session.id)

      # Verify total remaining messages
      user_messages = Enum.filter(updated_session.messages, &(&1.role == :user))
      assert length(user_messages) == 1

      # Get the remaining failed message
      current_failed_messages =
        Enum.filter(updated_session.messages, &(&1.status == :error))

      assert length(current_failed_messages) == 1

      last_remaining_message = List.first(user_messages)

      assert has_element?(view, "#retry-message-#{last_remaining_message.id}")
      refute has_element?(view, "#cancel-message-#{last_remaining_message.id}")

      # Compare with single message session behavior
      single_message_session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "Hello", status: :error, user: user}
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand", chat: single_message_session.id]}"
        )

      render_async(view)

      # Verify single message session only shows retry button
      assert has_element?(
               view,
               "#retry-message-#{List.first(single_message_session.messages).id}"
             )

      refute has_element?(
               view,
               "#cancel-message-#{List.first(single_message_session.messages).id}"
             )
    end

    @tag email: "user@openfn.org"
    test "AI Assistant renders custom component for collecting feedback", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      on_exit(fn -> Application.delete_env(:lightning, :ai_feedback) end)

      Application.put_env(:lightning, :ai_feedback, %{
        component: fn assigns ->
          ~H"""
          <div id="ai-feedback">Hello from AI Feedback</div>
          """
        end
      })

      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "assistant", "content" => "Hello, World!"}
                 ]
               }
             }}
        end
      )

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :assistant, content: "Hello, World!"}
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      view |> element("#get-started-with-ai-btn") |> render_click()

      view |> element("#session-#{session.id}") |> render_click()

      assert_patch(view)

      feedback_el = element(view, "#ai-feedback")

      assert has_element?(feedback_el)

      assert render(feedback_el) =~ "Hello from AI Feedback"
    end
  end

  describe "Allow low priority access users to retry steps and create workorders" do
    setup do
      project = insert(:project)

      high_priority_user =
        insert(:user,
          email: "amy@openfn.org",
          first_name: "Amy",
          last_name: "Ly"
        )

      low_priority_user =
        insert(:user,
          email: "ana@openfn.org",
          first_name: "Ana",
          last_name: "Ba"
        )

      insert(:project_user,
        project: project,
        user: high_priority_user,
        role: :admin
      )

      insert(:project_user,
        project: project,
        user: low_priority_user,
        role: :admin
      )

      workflow = insert(:simple_workflow, project: project)

      {:ok, snapshot} = Snapshot.create(workflow)

      %{jobs: [job], triggers: [trigger]} = workflow

      [input_dataclip, output_dataclip] =
        insert_list(2, :dataclip,
          body: %{player: "sadio mane"},
          project: workflow.project
        )

      %{runs: [run]} =
        insert(:workorder,
          trigger: trigger,
          dataclip: input_dataclip,
          workflow: workflow,
          snapshot: snapshot,
          state: :success,
          runs: [
            build(:run,
              starting_trigger: trigger,
              dataclip: input_dataclip,
              steps: [
                build(:step,
                  input_dataclip: input_dataclip,
                  output_dataclip: output_dataclip,
                  job: job,
                  inserted_at: Timex.now() |> Timex.shift(seconds: -10),
                  started_at: Timex.now() |> Timex.shift(seconds: -10),
                  snapshot: snapshot
                )
              ],
              inserted_at: Timex.now() |> Timex.shift(seconds: -12),
              snapshot: snapshot,
              state: :success
            )
          ]
        )

      %{
        project: project,
        high_priority_user: high_priority_user,
        low_priority_user: low_priority_user,
        workflow: workflow,
        snapshot: snapshot,
        run: run,
        job: job
      }
    end

    test "Users with low priority access to the workflow canvas will automatically be locked in a snapshot when the high prior uses saves the workflow",
         %{
           conn: conn,
           project: project,
           workflow: workflow,
           snapshot: snapshot,
           run: run,
           job: job,
           high_priority_user: high_priority_user,
           low_priority_user: low_priority_user
         } do
      {high_priority_view, low_priority_view} =
        access_views(
          conn,
          project,
          workflow,
          run,
          job,
          high_priority_user,
          low_priority_user
        )

      assert high_priority_view
             |> has_element?("#inspector-workflow-version", "latest")

      assert low_priority_view
             |> has_element?("#inspector-workflow-version", "latest")

      high_priority_view |> select_node(%{id: job.id})

      high_priority_view |> click_edit(%{id: job.id})

      high_priority_view |> change_editor_text("Job expression 1")

      high_priority_view |> form("#workflow-form") |> render_submit()

      assert high_priority_view
             |> has_element?("#inspector-workflow-version", "latest")

      refute_eventually(
        low_priority_view
        |> has_element?("#inspector-workflow-version", "latest"),
        30_000
      )

      assert low_priority_view
             |> has_element?(
               "#inspector-workflow-version",
               "#{String.slice(snapshot.id, 0..6)}"
             )

      assert low_priority_view |> render() =~
               "This workflow has been updated. You&#39;re no longer on the latest version."

      workflow = Repo.reload(workflow)

      assert workflow.lock_version == snapshot.lock_version + 1
    end
  end

  describe "run viewer" do
    test "user can toggle their preferred log levels", %{
      conn: conn,
      project: project,
      user: user
    } do
      %{triggers: [trigger], jobs: [job_1 | _rest]} =
        workflow = insert(:simple_workflow, project: project) |> with_snapshot()

      workflow = Lightning.Repo.reload(workflow)

      snapshot = Lightning.Workflows.Snapshot.get_current_for(workflow)

      dataclip = build(:http_request_dataclip, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          state: "failed",
          error_type: "CompileError",
          dataclip: dataclip,
          steps: [
            build(:step,
              job: job_1,
              snapshot: snapshot,
              input_dataclip: dataclip,
              exit_reason: "fail",
              error_type: "CompileError",
              started_at: DateTime.utc_now(),
              finished_at: DateTime.utc_now()
            )
          ]
        )

      insert(:log_line, run: run)
      insert(:log_line, run: run, step: hd(run.steps))

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{%{a: run.id, m: "expand", s: job_1.id}}"
        )

      run_view = find_live_child(view, "run-viewer-#{run.id}")

      render_async(run_view)
      assert render(run_view) =~ "Configure log levels"

      # when the user has not set their preference, we assume they want info
      assert user.preferences["desired_log_level"] |> is_nil()
      log_viewer = run_view |> element("#run-log-#{run.id}")

      # info log level is set in the viewer element
      assert log_viewer_selected_level(log_viewer) == "info"

      # try choosing another level
      for log_level <- ["debug", "info", "error", "warn"] do
        run_view
        |> form("#run-log-#{run.id}-filter-form")
        |> render_change(%{desired_log_level: log_level})

        # selected level is set in the viewer
        assert log_viewer_selected_level(log_viewer) == log_level

        # the preference is saved with expected levels
        updated_user = Repo.reload(user)
        assert updated_user.preferences["desired_log_level"] == log_level
      end
    end
  end

  defp log_viewer_selected_level(log_viewer) do
    log_viewer
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("data-log-level")
    |> hd()
  end

  defp access_views(
         conn,
         project,
         workflow,
         run,
         job,
         high_priority_user,
         low_priority_user
       ) do
    {:ok, high_priority_view, _html} =
      live(
        log_in_user(conn, high_priority_user),
        ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job, m: "expand"]}"
      )

    {:ok, low_priority_view, _html} =
      live(
        log_in_user(conn, low_priority_user),
        ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job, m: "expand"]}"
      )

    {high_priority_view, low_priority_view}
  end

  defp skip_disclaimer(user, read_at \\ DateTime.utc_now() |> DateTime.to_unix()) do
    Ecto.Changeset.change(user, %{
      preferences: %{"ai_assistant.disclaimer_read_at" => read_at}
    })
    |> Lightning.Repo.update!()
  end
end
