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
  import Phoenix.LiveViewTest
  import Mox

  alias Lightning.Auditing.Audit
  alias Lightning.Helpers
  alias Lightning.Repo

  setup :stub_apollo_unavailable
  alias Lightning.Workflows
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias LightningWeb.CredentialLiveHelpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "initial YAML generation" do
    setup :create_workflow

    test "pushes generate_workflow_code on first mount", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
        )

      assert_push_event(view, "generate_workflow_code", %{})
    end

    test "fires after a new workflow is created on the canvas", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new", on_error: :raise)

      select_template(view, "base-webhook-template")
      render_click(view, "save")

      assert_push_event(view, "generate_workflow_code", %{})
    end
  end

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
          ~p"/projects/#{project.id}/w/#{job.workflow_id}?s=#{job.id}&v=#{workflow.lock_version}",
          on_error: :raise
        )

      assert has_element?(view, "#job-pane-#{job.id}")

      view |> element("#new-credential-button") |> render_click()

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
          ~p"/projects/#{project.id}/w/#{job.workflow_id}?s=#{job.id}&v=#{workflow.lock_version}",
          on_error: :raise
        )

      view |> element("#new-credential-button") |> render_click()

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
             |> has_element?(
               ~S{select[name='credential_selector'] option},
               "newly created credential"
             ),
             "Should have the project credential available"
    end
  end

  describe "new" do
    test "builds a new workflow", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new", on_error: :raise)

      select_template(view, "base-webhook-template")

      # Naively add a job via the editor (calling the push-change event)
      assert view
             |> push_patches_to_view([add_job_patch()])

      # The server responds with a patch with any further changes
      assert_reply(
        view,
        %{
          patches: [
            %{op: "add", path: "/jobs/0/project_credential_id", value: nil},
            %{op: "add", path: "/jobs/0/keychain_credential_id", value: nil},
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
                },
                %{}
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
        live(conn, ~p"/projects/#{project.id}/w/new", on_error: :raise)

      {view, parsed_template} = select_template(view, "base-webhook-template")

      workflow_name = view |> get_workflow_params() |> Map.get("name")

      assert workflow_name == parsed_template["name"]

      # save button is not present
      refute view
             |> element("button[type='submit'][form='workflow-form'][disabled]")
             |> has_element?()

      refute view
             |> element("button[type='submit'][form='workflow-form']")
             |> has_element?()

      # settings panel is not preset
      refute has_element?(view, "#toggle-settings")

      # selecting a job doesn't open the panel
      {job, _, _} = select_first_job(view)
      path = assert_patch(view)

      # this v=0 is not actually what happens in the UI. The test helper select_first_job blindly
      # passes the workflow_version
      assert path == ~p"/projects/#{project.id}/w/new?s=#{job.id}&v=0"
      refute render(view) =~ "Job Name"
      refute has_element?(view, "input[name='workflow[jobs][0][name]']")

      # the panel for creating workflow appears
      html = render(view)
      assert html =~ "Describe your workflow"
      assert has_element?(view, "form#search-templates-form")
      assert has_element?(view, "form#choose-workflow-template-form")

      # click continue
      view |> render_click("save")

      workflow = get_assigns(view) |> Map.get(:workflow)

      # now let's fill in the name
      workflow_name = "My Workflow"

      view
      |> form("#workflow-form")
      |> render_change(workflow: %{name: workflow_name})

      # the panel disappears
      html = render(view)
      refute html =~ "Describe your workflow"
      refute has_element?(view, "form#search-templates-form")
      refute has_element?(view, "form#choose-workflow-template-form")

      # save button is now present
      assert view
             |> element("button", "Save")
             |> has_element?()

      # toggle settings panel button is now preset
      assert has_element?(view, "#toggle-settings")

      # selecting a job now opens the panel
      {job, _, _} = select_first_job(view)
      path = assert_patch(view)

      assert path ==
               ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job.id}&v=#{workflow.lock_version - 1}"

      assert render(view) =~ "Job Name"
      assert has_element?(view, "input[name='workflow[jobs][0][name]']")

      view |> fill_job_fields(job, %{name: "My Job"})

      # this has been inversed. ideally, it should not select latest by default
      # but given that @latest is set in the Job schema, it will alwasy get selected
      assert view |> selected_adaptor_version_element(job) |> render() =~
               ~r(value="@openfn/[a-z-]+@latest"),
             "should have @latest selected by default"

      view |> element("#new-credential-button") |> render_click()

      view |> CredentialLiveHelpers.select_credential_type("dhis2")

      view |> CredentialLiveHelpers.click_continue()

      # Creating a new credential from the Job panel
      view
      |> CredentialLiveHelpers.fill_credential(%{
        name: "My Credential",
        body: %{username: "foo", password: "bar", hostUrl: "http://someurl"}
      })

      view |> CredentialLiveHelpers.click_save()

      assert view |> selected_credential_name(job) == "My Credential"

      # Editing the Jobs' body
      view |> click_edit(job)

      view |> change_editor_text("some body")

      close_job_edit_view(view, job)

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
        fn %{type: :activate_workflow}, _context -> :ok end
      )

      # subscribe to workflow events
      Lightning.Workflows.subscribe(project.id)

      click_save(view)

      assert %{id: workflow_id} =
               Lightning.Repo.one(
                 from(w in Workflow,
                   where:
                     w.project_id == ^project.id and w.name == ^workflow_name
                 )
               )

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow_id}?#{[s: job.id]}"
      )

      assert render(view) =~ "Workflow saved"

      # workflow updated event is emitted
      assert_received %Lightning.Workflows.Events.WorkflowUpdated{
        workflow: %{id: ^workflow_id}
      }
    end

    @tag role: :editor
    test "creating a new workflow via template copies the name of the template",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new", on_error: :raise)

      select_template(view, "base-webhook-template")

      # the panel for creating workflow is visible
      html = render(view)
      assert html =~ "Describe your workflow"
      assert has_element?(view, "form#search-templates-form")
      assert has_element?(view, "form#choose-workflow-template-form")

      # lets select the cron one
      template_id = "base-cron-template"
      cron_template_name = "Scheduled Workflow"

      view
      |> form("#choose-workflow-template-form", %{template_id: template_id})
      |> render_change()

      assert view
             |> element(
               "form#choose-workflow-template-form label[data-selected='true']"
             )
             |> render() =~ cron_template_name

      # lets dummy send the content or base template
      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      payload = %{
        "triggers" => [%{"id" => trigger_id, "type" => "webhook"}],
        "jobs" => [
          %{
            "id" => job_id,
            "name" => "random job",
            "body" => "// comment"
          }
        ],
        "edges" => [
          %{
            "id" => Ecto.UUID.generate(),
            "source_trigger_id" => trigger_id,
            "condition_type" => "always",
            "target_job_id" => job_id
          }
        ]
      }

      view
      |> with_target("#new-workflow-panel")
      |> render_click("template-parsed", %{"workflow" => payload})

      # click continue
      view |> element("button#create_workflow_btn") |> render_click()

      click_save(view)

      expected_workflow_name = "Untitled workflow"

      assert Lightning.Repo.exists?(
               from(w in Workflow,
                 where:
                   w.project_id == ^project.id and
                     w.name == ^expected_workflow_name
               )
             )
    end

    @tag role: :editor
    test "creating a new workflow via import handles empty name",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=import",
          on_error: :raise
        )

      # Generate IDs for the workflow components
      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      # Send workflow with empty name
      view
      |> with_target("#new-workflow-panel")
      |> render_click("workflow-parsed", %{
        "workflow" => %{
          "name" => "",
          "triggers" => [%{"id" => trigger_id, "type" => "webhook"}],
          "jobs" => [
            %{
              "id" => job_id,
              "name" => "random job",
              "body" => "// comment"
            }
          ],
          "edges" => [
            %{
              "id" => Ecto.UUID.generate(),
              "source_trigger_id" => trigger_id,
              "condition_type" => "always",
              "target_job_id" => job_id
            }
          ]
        }
      })

      # click continue
      view |> element("button#create_workflow_btn") |> render_click()

      click_save(view)

      expected_workflow_name = "Untitled workflow"

      assert Lightning.Repo.exists?(
               from(w in Workflow,
                 where:
                   w.project_id == ^project.id and
                     w.name == ^expected_workflow_name
               )
             )
    end

    @tag role: :editor
    test "creating a new workflow via import", %{conn: conn, project: project} do
      {:ok, view, _html} =
        conn
        |> live(~p"/projects/#{project}/w/new")

      assert view
             |> element("#import-workflow-btn")
             |> render_click() =~ "Paste your YAML content here"

      # Test with valid payload
      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      valid_payload = %{
        "name" => "Test Workflow",
        "jobs" => [
          %{
            "id" => job_id,
            "name" => "Test Job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(state => state)"
          }
        ],
        "triggers" => [
          %{
            "id" => trigger_id,
            "type" => "webhook",
            "enabled" => true
          }
        ],
        "edges" => [
          %{
            "id" => edge_id,
            "source_trigger_id" => trigger_id,
            "target_job_id" => job_id,
            "condition_type" => "always",
            "enabled" => true
          }
        ]
      }

      view
      |> with_target("#new-workflow-panel")
      |> render_click("workflow-parsed", %{"workflow" => valid_payload})

      refute view
             |> element("#create_workflow_btn")
             |> render() =~ "disabled=\"disabled\""

      # Test with invalid payload (missing required fields)
      invalid_payload = %{
        "jobs" => [
          %{
            "id" => Ecto.UUID.generate(),
            "name" => "Test Job"
          }
        ]
      }

      view |> render_click("choose-another-method", %{"method" => "import"})

      view
      |> with_target("#new-workflow-panel")
      |> render_click("workflow-parsed", %{"workflow" => invalid_payload})

      assert view
             |> element("#create_workflow_btn")
             |> render() =~ "disabled=\"disabled\""
    end

    @tag role: :editor
    test "auditing snapshot creation", %{
      conn: conn,
      project: project,
      user: %{id: user_id}
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new")

      {view, _parsed_workflow} = select_template(view, "base-cron-template")

      view |> render_click("save")

      workflow_name = "My Workflow"

      view
      |> form("#workflow-form")
      |> render_change(workflow: %{name: workflow_name})

      {job, _, _} = view |> select_first_job()

      view |> fill_job_fields(job, %{name: "My Job"})

      view |> element("#new-credential-button") |> render_click()

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

      view |> render_click("save")

      assert %{id: workflow_id} =
               Lightning.Repo.one(
                 from(w in Workflow,
                   where:
                     w.project_id == ^project.id and w.name == ^workflow_name
                 )
               )

      audit_query = from(a in Audit, where: a.event == "snapshot_created")

      audit_events = Lightning.Repo.all(audit_query)

      # There should be 2 audit events - one for initial creation, one for save-and-sync
      assert length(audit_events) == 2

      Enum.each(audit_events, fn audit_event ->
        assert %{
                 actor_id: ^user_id,
                 item_id: ^workflow_id,
                 item_type: "workflow"
               } = audit_event
      end)
    end

    @tag role: :viewer
    test "viewers can't create new workflows", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new", on_error: :raise)
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
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
        )

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
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
        )

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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: snapshot.lock_version]}",
          on_error: :raise
        )

      assert view
             |> has_element?(
               "[id='canvas-workflow-version'][aria-label='You are viewing a snapshot of this workflow that was taken on #{Helpers.format_date(snapshot.inserted_at, "%F at %T")}']",
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
               |> has_element?(
                 "input[name='snapshot[jobs][#{idx}][name]'][disabled]"
               )

        assert view |> has_element?("[id='adaptor-name'][disabled]")
        assert view |> has_element?("[id='adaptor-version'][disabled]")

        assert view
               |> has_element?("select[name='credential_selector'][disabled]")

        view |> click_edit(job)

        assert view
               |> has_element?(
                 "[id='inspector-workflow-version'][aria-label='You are viewing a snapshot of this workflow that was taken on #{Helpers.format_date(snapshot.inserted_at, "%F at %T")}']",
                 version
               )

        view
        |> has_element?("[id='manual_run_form_dataclip_id'][disabled]")

        # TODO: There is an issue with the new jsx approach, this attribute
        # is no longer present in the DOM. It looks like LiveView doesn't
        # render script tags while testing.
        # It should look a little bit like this when runnin the server:
        # <script id="JobEditor-1" type="application/json" ... data-react-name="JobEditor" phx-hook="ReactComponent">
        #   {..."disabled_message":"You can't edit while viewing a snapshot, switch to the latest version."}
        # </script>

        # assert view
        #        |> has_element?(
        #          "[id='job-editor-#{job.id}'][data-disabled='true'][data-disabled-message=\"You can't edit while viewing a snapshot, switch to the latest version.\""
        #        )

        assert view
               |> has_element?("[id='version-switcher-toggle-#{job.id}]")

        assert view |> save_is_disabled?()
      end)

      snapshot.edges
      |> Enum.with_index()
      |> Enum.each(fn {edge, idx} ->
        view |> select_node(edge, workflow.lock_version)

        assert view
               |> has_element?(
                 "select[name='snapshot[edges][#{idx}][condition_type]'][disabled]"
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
                 "input[name='snapshot[triggers][#{idx}][enabled]'][disabled]"
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

      refute view |> save_is_disabled?()
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: snapshot.lock_version]}",
          on_error: :raise
        )

      last_edge = List.last(snapshot.edges)

      existing_audit_ids = Audit |> Repo.all() |> Enum.map(& &1.id)
      existing_snapshot_ids = Snapshot |> Repo.all() |> Enum.map(& &1.id)

      view |> select_node(last_edge, snapshot.lock_version)

      force_event(view, :manual_run_submit, %{})

      force_event(view, :rerun, nil, nil)

      snapshots_query =
        from(s in Snapshot, where: s.id not in ^existing_snapshot_ids)

      [%{id: latest_snapshot_id}] = Lightning.Repo.all(snapshots_query)

      audit_query =
        from(a in Audit, where: a.id not in ^existing_audit_ids)

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
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run_1, s: job_1, m: "expand", v: run_1.snapshot.lock_version]}",
          on_error: :raise
        )

      run_1_version = String.slice(run_1.snapshot.id, 0..6)

      assert view
             |> has_element?(
               "[id='inspector-workflow-version'][aria-label='You are viewing a snapshot of this workflow that was taken on #{Helpers.format_date(run_1.snapshot.inserted_at, "%F at %T")}']",
               run_1_version
             )

      assert view
             |> has_element?(
               "#job-editor-panel-panel-header-title",
               "Editor (read-only)"
             )

      # See: line 563
      # assert view
      #        |> has_element?(
      #          "[id='job-editor-#{job_1.id}'][data-disabled='true'][data-source='#{job_1.body}'][data-disabled-message=\"You can't edit while viewing a snapshot, switch to the latest version.\"]"
      #        )

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

      # See: line 563
      # assert view
      #        |> has_element?(
      #          "[id='job-editor-#{job_1.id}'][data-disabled-message=''][data-disabled='false'][data-source='#{job_2.body}']"
      #        )

      refute view
             |> has_element?("select[name='manual[dataclip_id]'][disabled]")

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
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job_to_delete, m: "expand", v: run.snapshot.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, m: "settings"]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
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

      # the current implmentation simply sends `save` the event, it does
      # not submit the form. I'm mimicking that here
      assert view |> render_submit("save") =~ "Workflow saved"

      assert Lightning.Repo.reload(workflow).concurrency == 5

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
            ~p"/projects/#{project.id}/w/#{workflow.id}",
            on_error: :raise
          )

        view
        |> element("#toggle-settings")
        |> render_click()

        assert view
               |> element("#toggle-control-toggle-workflow-logs-btn")
               |> render() =~ "opacity-50 cursor-not-allowed"

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
            ~p"/projects/#{project.id}/w/#{workflow.id}",
            on_error: :raise
          )

        view
        |> element("#toggle-settings")
        |> render_click()

        refute view
               |> element("#toggle-control-toggle-workflow-logs-btn")
               |> render() =~ "opacity-50 cursor-not-allowed"

        assert has_element?(
                 view,
                 "#toggle-workflow-logs-btn"
               )

        view
        |> form("#workflow-form")
        |> render_change(workflow: %{enable_job_logs: "false"})

        assert workflow.enable_job_logs == true

        # send a save event
        view |> render_submit("save")

        assert assert_patch(view) =~
                 ~p"/projects/#{project.id}/w/#{workflow.id}?m=settings"

        assert Repo.reload(workflow).enable_job_logs == false

        GenServer.stop(view.pid)
      end
    end

    test "users can view workflow as code", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}",
            on_error: :raise
          )

        view
        |> element("#toggle-settings")
        |> render_click()

        assert assert_patch(view) =~
                 ~p"/projects/#{project.id}/w/#{workflow.id}?m=settings"

        view |> element("a#view-workflow-as-yaml-link") |> render_click()

        assert assert_patch(view) =~
                 ~p"/projects/#{project.id}/w/#{workflow.id}?m=code"

        expected_download_name =
          String.replace(workflow.name, " ", "-") <> ".yaml"

        assert has_element?(
                 view,
                 "#download-workflow-code-btn[data-file-name='#{expected_download_name}']"
               )

        assert has_element?(view, "#copy-workflow-code-btn")

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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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

    test "displays warning when js expression contains unwanted words", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
        )

      warning_text =
        "Warning: this expression appears to contain unsafe functions (eval, require, import, process, await) that may cause your workflow to fail"

      edge_to_edit = Enum.at(workflow.edges, 1)
      view |> select_node(edge_to_edit)

      # change to js_expression
      html =
        view
        |> form("#workflow-form", %{
          "workflow" => %{
            "edges" => %{"1" => %{"condition_type" => "js_expression"}}
          }
        })
        |> render_change()

      assert html =~ "Matches a Javascript Expression"
      refute html =~ warning_text

      html =
        view
        |> form("#workflow-form", %{
          "workflow" => %{
            "edges" => %{
              "1" => %{
                "condition_label" => "My JS Expression",
                "condition_expression" => "eval"
              }
            }
          }
        })
        |> render_change()

      assert html =~ warning_text
    end

    @tag role: :editor
    test "can delete a job", %{conn: conn, project: project, workflow: workflow} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project}/w/#{workflow}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project}/w/#{workflow}?s=#{job_a}&v=#{workflow.lock_version}",
          on_error: :raise
        )

      assert view |> delete_job_button_is_disabled?(job_a)

      assert html =~
               "You can&#39;t delete a step that other downstream steps depend on"

      assert view |> force_event(:delete_node, job_a) =~
               "Delete all descendant steps first"

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?s=#{job_b}&v=#{workflow.lock_version}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{edge.id}&v=#{workflow.lock_version}",
          on_error: :raise
        )

      idx = get_index_of_edge(view, edge)

      assert html =~ "Enabled"

      assert view
             |> element("input[name='workflow[edges][#{idx}][enabled]']")
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
             |> element(
               "input[name='workflow[edges][#{idx}][enabled]'][checked]"
             )
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
        live(conn, ~p"/projects/#{project}/w/new", on_error: :raise)

      select_template(view, "base-webhook-template")

      push_patches_to_view(view, initial_workflow_patchset(project))

      # click continue
      view |> element("button#create_workflow_btn") |> render_click()

      view
      |> form("#workflow-form")
      |> render_change(workflow: %{name: "My Workflow"})

      {job, _, _} = select_first_job(view)

      fill_job_fields(view, job, %{name: "My Job"})

      click_edit(view, job)

      change_editor_text(view, "some body")

      # html = click_save(view)
      html = trigger_save(view)

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
        live(conn, ~p"/projects/#{project}/w/new", on_error: :raise)

      select_template(view, "base-webhook-template")

      push_patches_to_view(view, initial_workflow_patchset(project))

      # click continue
      view |> element("button#create_workflow_btn") |> render_click()

      view
      |> form("#workflow-form")
      |> render_change(workflow: %{name: "My Workflow"})

      {job, _, _} = select_first_job(view)

      fill_job_fields(view, job, %{name: "My Job"})

      click_edit(view, job)

      change_editor_text(view, "some body")

      close_job_edit_view(view, job)

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
          ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{cron_workflow.id}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{webhook_workflow.id}",
          on_error: :raise
        )

      assert view
             |> has_element?(
               "#toggle-container-workflow[aria-label='This workflow is active (webhook trigger enabled)']"
             )
    end

    @tag skip: "component moved to react"
    test "manual run form body remains unchanged even after save workflow form is submitted",
         %{conn: conn, project: project, test: test} do
      %{jobs: [job_1, job_2 | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job_1, m: "expand"]}",
          on_error: :raise
        )

      body = Jason.encode!(%{test: test})

      body_part = to_string(test)

      refute view |> element("#manual_run_form") |> render() =~ body_part

      assert view
             |> form("#manual_run_form")
             |> render_change(manual: %{body: body}) =~ body_part

      view |> close_job_edit_view(job_1)

      # submit workflow form
      view |> form("#workflow-form") |> render_submit()

      view
      |> render_patch(
        ~p"/projects/#{project}/w/#{workflow}?#{[m: "expand", s: job_1.id]}"
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
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
        )

      fun = fn ->
        view
        |> editor_element()
        |> render_hook("workflow_editor_metrics_report", %{"metrics" => metrics})
      end

      assert capture_log(fun) =~ ~r/foo-bar-event/
      assert capture_log(fun) =~ ~r/#{workflow_id}/
    end

    @tag role: :editor
    test "can change job name, adaptor, version, and credential sequentially", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      project_credential =
        insert(:project_credential,
          project: project,
          credential: build(:credential)
        )

      keychain_credential =
        insert(:keychain_credential, project: project)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
        )

      # Select the first job
      job = hd(workflow.jobs)
      view |> select_node(job, workflow.lock_version)

      # Step 1: Change job name
      new_job_name = "Updated Job Name"

      view
      |> form("#workflow-form", %{
        "workflow" => %{
          "jobs" => %{
            "0" => %{
              "name" => new_job_name
            }
          }
        }
      })
      |> render_change()

      # Step 2: Change adaptor
      view |> change_adaptor(job, "@openfn/language-dhis2")
      view |> trigger_save()

      # Step 3: Change adaptor version to something specific (not @latest)
      specific_version = "@openfn/language-dhis2@3.0.4"
      view |> change_adaptor_version(specific_version)

      assert view
             |> credential_options()
             |> Enum.reject(&(&1.text == "")) ==
               [
                 %{
                   text: project_credential.credential.name,
                   value: project_credential.id
                 },
                 %{text: keychain_credential.name, value: keychain_credential.id}
               ]

      view |> change_credential(job, project_credential)

      assert view |> selected_credential_name() ==
               project_credential.credential.name

      view |> trigger_save()

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: job.id, v: workflow.lock_version]}"
      )

      job = Lightning.Repo.reload(job)
      assert job.adaptor == specific_version
      assert job.name == new_job_name
      assert job.project_credential_id == project_credential.id

      view |> change_credential(job, keychain_credential)
      assert view |> selected_credential_name() == keychain_credential.name

      view |> trigger_save()

      job = Lightning.Repo.reload(job)
      assert job.project_credential_id == nil
      assert job.keychain_credential_id == keychain_credential.id
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
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
        )

      refute view |> has_element?("button[phx-click='toggle_github_sync_modal']")
    end

    @tag role: :editor
    test "can be done when creating a new workflow", %{
      conn: conn,
      project: project,
      repo_connection: repo_connection
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new", on_error: :raise)

      {view, _parsed_workflow} = select_template(view, "base-webhook-template")

      view |> render_click("save")

      workflow = get_assigns(view) |> Map.get(:workflow)

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}"
      )

      workflow_name = "My Workflow"

      view
      |> form("#workflow-form")
      |> render_change(workflow: %{name: workflow_name})

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
      render_hook(view, "toggle_github_sync_modal")
      assert has_element?(view, "#github-sync-modal")
      # modal form exists
      assert view |> has_element?("form#github-sync-modal-form")
      assert render_async(view) =~ "Save and sync changes to GitHub"

      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)
      expect_create_workflow_dispatch(repo_connection.repo, "openfn-pull.yml")

      # submit form
      view
      |> form("#github-sync-modal-form")
      |> render_submit(%{
        "github_sync" => %{"commit_message" => "some message"}
      })

      assert workflow =
               Lightning.Repo.one(
                 from(w in Workflow,
                   where:
                     w.project_id == ^project.id and w.name == ^workflow_name
                 )
               )

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[m: "expand", s: job.id]}"
      )

      assert render(view) =~ "Workflow saved and sync requested. Check the"

      link_to_actions =
        "https://www.github.com/" <> repo_connection.repo <> "/actions"

      assert has_element?(
               view,
               ~s{div[data-flash-kind='info'] [href="#{link_to_actions}"][target="_blank"]},
               "Github actions"
             )

      refute has_element?(view, "#github-sync-modal")
    end

    @tag :capture_log
    test "does not close the github modal when Github sync fails", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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
      |> form("#github-sync-modal-form")
      |> render_submit(%{"github_sync" => %{"commit_message" => "some message"}})

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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version]}",
          on_error: :raise
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

      trigger_save(high_priority_view)

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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{%{a: run.id, m: "expand", s: job_1.id}}",
          on_error: :raise
        )

      run_view = find_live_child(view, "run-viewer-#{run.id}")

      render_async(run_view)

      assert run_view
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find("span.hero-adjustments-vertical + span")
             |> Floki.text() ==
               "info"

      # when the user has not set their preference, we assume they want info
      assert user.preferences["desired_log_level"] |> is_nil()
      log_viewer = run_view |> element("#run-log-#{run.id}")

      # info log level is set in the viewer element
      assert log_viewer_selected_level(log_viewer) == "info"

      # try choosing another level
      for log_level <- ["debug", "info", "error", "warn"] do
        run_view
        |> element("#run-log-#{run.id}-filter-dropdown-#{log_level}-option")
        |> render_click(%{})

        # selected level is set in the viewer
        assert log_viewer_selected_level(log_viewer) == log_level

        # the preference is saved with expected levels
        updated_user = Repo.reload(user)
        assert updated_user.preferences["desired_log_level"] == log_level
      end
    end
  end

  describe "new manual run" do
    test "gets latest selectable dataclips",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      limit = 4
      search_text = ""

      dataclips =
        Enum.map(1..5, fn i ->
          insert(:dataclip,
            body: %{"body-field" => "body-value#{i}"},
            request: %{"headers" => "list"},
            type: :http_request,
            inserted_at: DateTime.add(DateTime.utc_now(), i, :millisecond)
          )
          |> tap(&insert(:step, input_dataclip: &1, job: job))
          |> then(fn %{body: body, request: request} = dataclip ->
            dataclip
            |> Repo.reload!()
            |> restore_listed(body, request)
            |> then(&%{&1 | body: nil})
          end)
        end)
        |> Enum.sort_by(& &1.inserted_at, :desc)
        |> Enum.take(limit)

      render_hook(view, "search-selectable-dataclips", %{
        "job_id" => job.id,
        "search_text" => search_text,
        "limit" => limit
      })

      assert_reply(view, %{dataclips: ^dataclips})
    end

    test "searches for dataclips by uuid",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      dataclip =
        insert(:dataclip,
          body: %{"body-field" => "body-value"},
          request: %{"headers" => "list"},
          type: :step_result
        )
        |> tap(&insert(:step, input_dataclip: &1, job: job))
        |> then(fn %{body: body, request: request} = dataclip ->
          dataclip
          |> Repo.reload!()
          |> restore_listed(body, request)
          |> then(&%{&1 | body: nil})
        end)

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=#{Ecto.UUID.generate()}",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: []})

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=#{dataclip.id}",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: [^dataclip]})
    end

    test "searches for dataclips by uuid prefix",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      dataclip =
        insert(:dataclip,
          body: %{"body-field" => "body-value"},
          request: %{"headers" => "list"},
          type: :step_result
        )
        |> tap(&insert(:step, input_dataclip: &1, job: job))
        |> then(fn %{body: body, request: request} = dataclip ->
          dataclip
          |> Repo.reload!()
          |> restore_listed(body, request)
          |> then(&%{&1 | body: nil})
        end)

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=#{Ecto.UUID.generate()}",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: []})

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=#{String.slice(dataclip.id, 0..3)}",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: [^dataclip]})

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=#{String.slice(dataclip.id, 0..3)}",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: [^dataclip]})

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" =>
            "query=#{String.slice(dataclip.id, 0..1)}&type=step_result",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: [^dataclip]})
    end

    test "searches for dataclips by type",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      insert(:dataclip,
        body: %{"body-field" => "body-value"},
        request: %{"headers" => "list"},
        type: :step_result
      )
      |> tap(&insert(:step, input_dataclip: &1, job: job))

      limit = 3

      dataclips =
        Enum.map(1..5, fn i ->
          insert(:dataclip,
            body: %{"body-field" => "body-value#{i}"},
            request: %{"headers" => "list"},
            type: :http_request
          )
          |> tap(&insert(:step, input_dataclip: &1, job: job))
          |> then(fn %{body: body, request: request} = dataclip ->
            dataclip
            |> Repo.reload!()
            |> restore_listed(body, request)
            |> then(&%{&1 | body: nil})
          end)
        end)
        |> Enum.sort_by(& &1.inserted_at, :desc)
        |> Enum.take(limit)

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "type=http_request",
          "limit" => limit
        }
      )

      assert_reply(view, %{dataclips: ^dataclips})
    end

    test "searches for dataclips created after a datetime",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      datetime_param = DateTime.utc_now()

      dataclips =
        Enum.map(-1..5, fn i ->
          type = if rem(i, 2) == 0, do: :http_request, else: :step_result
          request = if type == :http_request, do: %{"headers" => "list"}

          insert(:dataclip,
            body: %{"body-field" => "body-value#{i}"},
            request: request,
            type: type,
            inserted_at: DateTime.add(datetime_param, i, :minute)
          )
          |> tap(&insert(:step, input_dataclip: &1, job: job))
          |> then(fn %{body: body, request: request} = dataclip ->
            dataclip
            |> Repo.reload!()
            |> restore_listed(body, request)
            |> then(&%{&1 | body: nil})
          end)
        end)
        |> Enum.sort_by(& &1.inserted_at, :desc)
        |> Enum.take(5)

      search_text =
        %{
          "after" =>
            DateTime.to_iso8601(datetime_param |> DateTime.add(1, :minute))
            |> String.slice(0..15)
        }
        |> URI.encode_query()

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => search_text,
          "limit" => 10
        }
      )

      assert_reply(view, %{dataclips: ^dataclips})
    end

    test "searches for dataclips created after a date",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      starting_datetime = ~N[2025-05-15 00:00:00]

      dataclips =
        Enum.map(-1..5, fn i ->
          type = if rem(i, 2) == 0, do: :http_request, else: :step_result
          request = if type == :http_request, do: %{"headers" => "list"}

          insert(:dataclip,
            body: %{"body-field" => "body-value#{i}"},
            request: request,
            type: type,
            inserted_at: NaiveDateTime.add(starting_datetime, i * 5, :minute)
          )
          |> tap(&insert(:step, input_dataclip: &1, job: job))
          |> then(fn %{body: body, request: request} = dataclip ->
            dataclip
            |> Repo.reload!()
            |> restore_listed(body, request)
            |> then(&%{&1 | body: nil})
          end)
        end)
        |> Enum.drop(1)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      search_text =
        %{
          "after" =>
            starting_datetime
            |> NaiveDateTime.to_iso8601()
            |> String.slice(0..15)
        }
        |> URI.encode_query()

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => search_text,
          "limit" => 10
        }
      )

      assert_reply(view, %{dataclips: ^dataclips})
    end

    test "searches for dataclips from one type created after a date",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      starting_datetime = ~N[2025-05-15 00:00:00]

      dataclips =
        Enum.map(-1..5, fn i ->
          type = if rem(i, 2) == 0, do: :http_request, else: :step_result
          request = if type == :http_request, do: %{"headers" => "list"}

          insert(:dataclip,
            body: %{"body-field" => "body-value#{i}"},
            request: request,
            type: type,
            inserted_at: NaiveDateTime.add(starting_datetime, i * 5, :minute)
          )
          |> tap(&insert(:step, input_dataclip: &1, job: job))
          |> then(fn %{body: body, request: request} = dataclip ->
            dataclip
            |> Repo.reload!()
            |> restore_listed(body, request)
            |> then(&%{&1 | body: nil})
          end)
        end)
        |> Enum.drop(1)
        |> Enum.sort_by(& &1.inserted_at, :desc)
        |> Enum.filter(&(&1.type == :step_result))

      search_text =
        %{
          "after" =>
            NaiveDateTime.to_iso8601(starting_datetime)
            |> String.slice(0..15),
          "type" => "step_result"
        }
        |> URI.encode_query()

      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => search_text,
          "limit" => 10
        }
      )

      assert_reply(view, %{dataclips: ^dataclips})
    end

    test "gets run step and input dataclip",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      # Create a dataclip
      dataclip =
        insert(:dataclip,
          body: %{"input-field" => "input-value"},
          request: %{"headers" => "list"},
          type: :http_request
        )

      work_order = insert(:workorder, workflow: workflow, dataclip: dataclip)

      # Create run with step in one go using the factory pattern
      run =
        insert(:run,
          workflow: workflow,
          starting_job: job,
          dataclip: dataclip,
          work_order: work_order,
          steps: [
            build(:step, job: job, input_dataclip: dataclip)
          ]
        )

      expected_dataclip =
        dataclip
        |> Repo.reload!()
        |> restore_listed(%{"input-field" => "input-value"}, %{
          "headers" => "list"
        })
        |> then(&%{&1 | body: nil})

      expected_step_id = hd(run.steps).id

      render_hook(view, "get-run-step-and-input-dataclip", %{
        "run_id" => run.id,
        "job_id" => job.id
      })

      assert_reply(view, %{
        dataclip: ^expected_dataclip,
        run_step: %{id: ^expected_step_id}
      })
    end

    test "returns nil when no dataclip found for run and job",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      # Create a dataclip for the run (required by schema)
      dataclip = insert(:dataclip, body: %{"some" => "data"})

      # Create a run with a dataclip but no step for the specific job
      work_order = insert(:workorder, workflow: workflow, dataclip: dataclip)

      run =
        insert(:run,
          workflow: workflow,
          starting_job: job,
          dataclip: dataclip,
          work_order: work_order
        )

      # Intentionally not creating any step for this job to test the nil case

      render_hook(view, "get-run-step-and-input-dataclip", %{
        "run_id" => run.id,
        "job_id" => job.id
      })

      assert_reply(view, %{dataclip: nil, run_step: nil})
    end

    test "creates run from start job", %{
      conn: conn,
      project: project,
      test: test
    } do
      %{jobs: [job_1, _job_2 | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}",
          on_error: :raise
        )

      body = Jason.encode!(%{test: test})

      refute Lightning.Repo.get_by(Lightning.Run, starting_job_id: job_1.id)

      render_click(view, "manual_run_submit", %{
        manual: %{body: body},
        from_start: true
      })

      assert created_run =
               Lightning.Repo.get_by(Lightning.Run, starting_job_id: job_1.id)

      assert_redirected(view, ~p"/projects/#{project}/runs/#{created_run}")
    end

    test "creates run from specific job", %{
      conn: conn,
      project: project,
      test: test
    } do
      %{jobs: [_job_1, job_2 | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}",
          on_error: :raise
        )

      body = Jason.encode!(%{test: test})

      refute Lightning.Repo.get_by(Lightning.Run, starting_job_id: job_2.id)

      render_click(view, "manual_run_submit", %{
        manual: %{body: body},
        from_job: job_2.id
      })

      assert created_run =
               Lightning.Repo.get_by(Lightning.Run, starting_job_id: job_2.id)

      assert_redirected(view, ~p"/projects/#{project}/runs/#{created_run}")
    end

    test "can rerun",
         %{conn: conn, project: project, user: user} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      # Create a dataclip
      dataclip =
        insert(:dataclip,
          body: %{"input-field" => "input-value"},
          request: %{"headers" => "list"},
          type: :http_request
        )

      work_order = insert(:workorder, workflow: workflow, dataclip: dataclip)

      # Create run with step in one go using the factory pattern
      run =
        insert(:run,
          workflow: workflow,
          starting_job: job,
          dataclip: dataclip,
          work_order: work_order,
          steps: [
            build(:step, job: job, input_dataclip: dataclip)
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job.id, a: run.id, m: "workflow_input"]}",
          on_error: :raise
        )

      render_hook(view, "rerun", %{
        "run_id" => run.id,
        "step_id" => hd(run.steps).id,
        "via" => "job_panel"
      })

      created_run = Lightning.Repo.get_by(Lightning.Run, created_by_id: user.id)

      assert_redirected(view, ~p"/projects/#{project}/runs/#{created_run}")
    end

    test "searches for dataclips by name prefix",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      # Create named dataclips
      %{id: named_dataclip_id} =
        insert(:dataclip,
          name: "My Test Dataclip",
          body: %{"body-field" => "body-value"},
          type: :http_request,
          project: project
        )
        |> tap(&insert(:step, input_dataclip: &1, job: job))

      %{id: other_named_dataclip_id} =
        insert(:dataclip,
          name: "Another Dataclip",
          body: %{"body-field" => "body-value2"},
          type: :http_request,
          project: project
        )
        |> tap(&insert(:step, input_dataclip: &1, job: job))

      # Create dataclip without name
      insert(:dataclip,
        name: nil,
        body: %{"body-field" => "body-value3"},
        type: :http_request,
        project: project
      )
      |> tap(&insert(:step, input_dataclip: &1, job: job))

      # Test searching by name prefix "My"
      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=My",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: [%{id: ^named_dataclip_id}]})

      # Test searching by name prefix "Another"
      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=Another",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: [%{id: ^other_named_dataclip_id}]})

      # Test case insensitive search
      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=my",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: [%{id: ^named_dataclip_id}]})

      # Test no matches
      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "query=nonexistent",
          "limit" => 5
        }
      )

      assert_reply(view, %{dataclips: []})
    end

    test "searches for dataclips using named_only filter",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      # Create named dataclips
      %{id: named_dataclip1_id} =
        insert(:dataclip,
          name: "First Named",
          body: %{"body-field" => "body-value1"},
          request: %{"headers" => "list"},
          type: :http_request
        )
        |> tap(&insert(:step, input_dataclip: &1, job: job))

      %{id: named_dataclip2_id} =
        insert(:dataclip,
          name: "Second Named",
          body: %{"body-field" => "body-value2"},
          request: %{"headers" => "list"},
          type: :http_request
        )
        |> tap(&insert(:step, input_dataclip: &1, job: job))

      # Create dataclips without names
      insert(:dataclip,
        name: nil,
        body: %{"body-field" => "body-value3"},
        request: %{"headers" => "list"},
        type: :http_request
      )
      |> tap(&insert(:step, input_dataclip: &1, job: job))

      insert(:dataclip,
        name: nil,
        body: %{"body-field" => "body-value4"},
        request: %{"headers" => "list"},
        type: :http_request
      )
      |> tap(&insert(:step, input_dataclip: &1, job: job))

      # Test named_only filter
      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "named_only=true",
          "limit" => 10
        }
      )

      # Should return only named dataclips, ordered by inserted_at desc
      assert_reply(view, %{
        dataclips: [%{id: ^named_dataclip2_id}, %{id: ^named_dataclip1_id}]
      })

      # Test without named_only filter - should return all dataclips
      render_hook(
        view,
        "search-selectable-dataclips",
        %{
          "job_id" => job.id,
          "search_text" => "",
          "limit" => 10
        }
      )

      # Should return all 4 dataclips
      assert_reply(view, %{dataclips: dataclips})
      assert length(dataclips) == 4
    end

    test "update-dataclip-name event fails when user cannot edit workflow",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      # Set up user with viewer permission
      {conn, _user} = setup_project_user(conn, project, :viewer)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      # Create a dataclip
      dataclip =
        insert(:dataclip,
          name: "Original Name",
          body: %{"body-field" => "body-value"},
          request: %{"headers" => "list"},
          type: :http_request
        )

      # Try to update the dataclip name
      render_hook(
        view,
        "update-dataclip-name",
        %{
          "dataclip_id" => dataclip.id,
          "name" => "New Name"
        }
      )

      # Should return error message
      assert_reply(view, %{
        error: "You are not authorized to perform this action"
      })

      # Verify dataclip name was not changed in database
      updated_dataclip = Lightning.Repo.reload!(dataclip)
      assert updated_dataclip.name == "Original Name"
    end

    test "update-dataclip-name event fails when dataclip name is already in use",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      # Create a dataclip
      dataclip =
        insert(:dataclip,
          name: "Original Name",
          body: %{"body-field" => "body-value"},
          request: %{"headers" => "list"},
          type: :http_request,
          project: project
        )

      another_dataclip =
        insert(:dataclip,
          name: "Another Name",
          body: %{"body-field" => "body-value"},
          request: %{"headers" => "list"},
          type: :http_request,
          project: project
        )

      # Try to update the dataclip name
      render_hook(
        view,
        "update-dataclip-name",
        %{
          "dataclip_id" => dataclip.id,
          "name" => another_dataclip.name
        }
      )

      # Should return error message
      assert_reply(view, %{
        error: "dataclip name already in use"
      })

      # Verify dataclip name was not changed in database
      updated_dataclip = Lightning.Repo.reload!(dataclip)
      assert updated_dataclip.name == "Original Name"
    end

    test "update-dataclip-name event updates dataclip name successfully",
         %{conn: conn, project: project} do
      %{jobs: [job | _rest]} =
        workflow = insert(:complex_workflow, project: project)

      Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[s: job, m: "expand"]}",
          on_error: :raise
        )

      # Create a dataclip
      dataclip =
        insert(:dataclip,
          name: "Original Name",
          body: %{"body-field" => "body-value"},
          request: %{"headers" => "list"},
          type: :http_request
        )

      # Update the dataclip name
      assert render_hook(
               view,
               "update-dataclip-name",
               %{
                 "dataclip_id" => dataclip.id,
                 "name" => "New Name"
               }
             ) =~ "Label created. Dataclip will be saved permanently"

      # Should return updated dataclip
      assert_reply(view, %{dataclip: %{name: "New Name"}})

      # Verify dataclip name was changed in database
      updated_dataclip = Lightning.Repo.reload!(dataclip)
      assert updated_dataclip.name == "New Name"

      audit =
        Lightning.Repo.get_by(Lightning.Auditing.Audit,
          event: "label_created",
          item_id: dataclip.id
        )

      assert match?(
               %{
                 before: %{"name" => "Original Name"},
                 after: %{"name" => "New Name"}
               },
               audit.changes
             )

      # clear the dataclip name
      assert render_hook(
               view,
               "update-dataclip-name",
               %{
                 "dataclip_id" => dataclip.id,
                 "name" => ""
               }
             ) =~
               "Label deleted. Dataclip will be purged when your retention policy limit is reached"

      audit =
        Lightning.Repo.get_by(Lightning.Auditing.Audit,
          event: "label_deleted",
          item_id: dataclip.id
        )

      assert match?(
               %{
                 before: %{"name" => "New Name"},
                 after: %{"name" => nil}
               },
               audit.changes
             )
    end
  end

  describe "get-current-state event" do
    setup :create_workflow

    test "returns workflow params when no run is selected", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
        )

      render_hook(view, "get-current-state", %{})

      assert_reply(view, %{
        workflow_params: %{},
        run_steps: %{
          start_from: nil,
          steps: [],
          isTrigger: true,
          inserted_at: nil
        },
        run_id: nil,
        history: []
      })
    end

    test "returns workflow params with run steps and history when run is selected",
         %{
           conn: conn,
           project: project,
           workflow: workflow,
           snapshot: snapshot
         } do
      %{triggers: [trigger], jobs: [job | _]} = workflow

      dataclip = insert(:dataclip, project: project, body: %{"test" => "data"})

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: dataclip,
          state: :success,
          last_activity: DateTime.utc_now()
        )

      started_at = DateTime.utc_now() |> DateTime.add(-60, :second)
      finished_at = DateTime.utc_now() |> DateTime.add(-30, :second)

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot,
          state: :success,
          started_at: started_at,
          finished_at: finished_at,
          inserted_at: started_at
        )

      insert(:step,
        job: job,
        # Pass as a list
        runs: [run],
        snapshot: snapshot,
        input_dataclip: dataclip,
        started_at: started_at,
        finished_at: finished_at,
        exit_reason: "success",
        error_type: nil
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job, m: "expand"]}",
          on_error: :raise
        )

      render_hook(view, "get-current-state", %{})

      assert_reply(view, %{
        workflow_params: _workflow_params,
        run_steps: run_steps,
        run_id: run_id,
        history: history
      })

      assert run_id == run.id
      assert run_steps.start_from == trigger.id
      assert run_steps.isTrigger == true
      assert run_steps.inserted_at == started_at
      assert run_steps.run_by == nil

      assert length(run_steps.steps) == 1
      [step_data] = run_steps.steps
      assert step_data.job_id == job.id
      assert step_data.error_type == nil
      assert step_data.exit_reason == "success"
      assert step_data.started_at == started_at
      assert step_data.finished_at == finished_at

      assert length(history) == 1
      [work_order_data] = history
      assert work_order_data.id == work_order.id
      assert work_order_data.version == snapshot.lock_version
      assert work_order_data.state == :success
      assert work_order_data.last_activity == work_order.last_activity

      assert length(work_order_data.runs) == 1
      [run_data] = work_order_data.runs
      assert run_data.id == run.id
      assert run_data.state == :success
      assert run_data.error_type == nil
      assert run_data.started_at == started_at
      assert run_data.finished_at == finished_at
    end

    test "returns run steps with created_by user email when present", %{
      conn: conn,
      project: project,
      workflow: workflow,
      snapshot: snapshot,
      user: user
    } do
      %{triggers: [trigger], jobs: [job | _]} = workflow

      dataclip = insert(:dataclip, project: project, body: %{"test" => "data"})

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
          dataclip: dataclip,
          snapshot: snapshot,
          created_by: user
        )

      insert(:step, job: job, runs: [run], snapshot: snapshot)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job, m: "expand"]}",
          on_error: :raise
        )

      render_hook(view, "get-current-state", %{})

      assert_reply(view, %{run_steps: %{run_by: email}})
      assert email == user.email
    end

    test "handles job-started runs correctly", %{
      conn: conn,
      project: project,
      workflow: workflow,
      snapshot: snapshot
    } do
      %{jobs: [job | _]} = workflow

      dataclip = insert(:dataclip, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_job: job,
          starting_trigger: nil,
          dataclip: dataclip,
          snapshot: snapshot
        )

      insert(:step, job: job, runs: [run], snapshot: snapshot)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job, m: "expand"]}",
          on_error: :raise
        )

      render_hook(view, "get-current-state", %{})

      assert_reply(view, %{run_steps: run_steps})
      assert run_steps.start_from == job.id
      assert run_steps.isTrigger == false
    end

    test "handles runs with multiple steps and error states", %{
      conn: conn,
      project: project,
      workflow: workflow,
      snapshot: snapshot
    } do
      %{triggers: [trigger], jobs: [job1, job2 | _]} = workflow

      dataclip = insert(:dataclip, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: dataclip,
          state: :failed
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot,
          state: :failed,
          error_type: "RuntimeError"
        )

      insert(:step,
        job: job1,
        runs: [run],
        snapshot: snapshot,
        exit_reason: "success",
        error_type: nil
      )

      insert(:step,
        job: job2,
        runs: [run],
        snapshot: snapshot,
        exit_reason: "fail",
        error_type: "RuntimeError"
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job1, m: "history"]}",
          on_error: :raise
        )

      render_hook(view, "get-current-state", %{})

      assert_reply(view, %{run_steps: %{steps: steps}})
      assert length(steps) == 2

      [step1, step2] = steps
      assert step1.exit_reason == "success"
      assert step1.error_type == nil

      assert step2.exit_reason == "fail"
      assert step2.error_type == "RuntimeError"
    end

    test "returns multiple work orders in history", %{
      conn: conn,
      project: project,
      workflow: workflow,
      snapshot: snapshot1,
      user: user
    } do
      %{triggers: [trigger], jobs: [job | _]} = workflow

      {:ok, updated_workflow} =
        Workflows.change_workflow(workflow, %{name: "Updated Workflow"})
        |> Workflows.save_workflow(user)

      snapshot2 = Lightning.Workflows.Snapshot.get_current_for(updated_workflow)

      dataclip = insert(:dataclip, project: project)

      work_order1 =
        insert(:workorder,
          workflow: updated_workflow,
          snapshot: snapshot1,
          dataclip: dataclip,
          state: :success
        )

      run1 =
        insert(:run,
          work_order: work_order1,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot1,
          state: :success
        )

      work_order2 =
        insert(:workorder,
          workflow: updated_workflow,
          snapshot: snapshot2,
          dataclip: dataclip,
          state: :pending
        )

      run2 =
        insert(:run,
          work_order: work_order2,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot2,
          state: :started
        )

      insert(:step, job: job, runs: [run1], snapshot: snapshot1)
      insert(:step, job: job, runs: [run2], snapshot: snapshot2)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{updated_workflow}?#{[a: run2, s: job, m: "expand"]}",
          on_error: :raise
        )

      render_hook(view, "get-current-state", %{})

      assert_reply(view, %{history: history})
      assert length(history) == 2

      versions = Enum.map(history, & &1.version)
      assert snapshot1.lock_version in versions
      assert snapshot2.lock_version in versions
    end

    test "canvas is disabled when appropriate", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      {:ok, _snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}",
          on_error: :raise
        )

      render_hook(view, "get-current-state", %{})

      assert_push_event(view, "set-disabled", %{disabled: true})
    end
  end

  describe "run selection history mode" do
    setup :create_workflow

    test "loads historical run data when accessing history mode", %{
      conn: conn,
      project: project,
      workflow: workflow,
      snapshot: snapshot
    } do
      %{triggers: [trigger], jobs: [job | _]} = workflow

      dataclip = insert(:dataclip, project: project)

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
          dataclip: dataclip,
          snapshot: snapshot
        )

      insert(:step,
        job: job,
        runs: [run],
        snapshot: snapshot,
        exit_reason: "success"
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?m=history&v=#{snapshot.lock_version}&a=#{run.id}&s=#{job.id}"
        )

      assert_push_event(view, "patch-runs", %{
        run_id: run_id,
        run_steps: run_steps
      })

      assert run_id == run.id
      assert run_steps.start_from == trigger.id
      assert length(run_steps.steps) == 1
    end

    test "handles history mode without selected job", %{
      conn: conn,
      project: project,
      workflow: workflow,
      snapshot: snapshot
    } do
      %{triggers: [trigger]} = workflow

      dataclip = insert(:dataclip, project: project)

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
          dataclip: dataclip,
          snapshot: snapshot
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}?m=history&v=#{snapshot.lock_version}&a=#{run.id}"
        )

      expected_run_id = run.id
      assert_push_event(view, "patch-runs", %{run_id: actual_run_id})
      assert actual_run_id == expected_run_id
    end

    test "canvas is disabled when workflow is deleted", %{
      conn: conn,
      project: project
    } do
      workflow =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      {:ok, _snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      assert_push_event(view, "set-disabled", %{disabled: true})
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
        ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job, m: "expand"]}",
        on_error: :raise
      )

    {:ok, low_priority_view, _html} =
      live(
        log_in_user(conn, low_priority_user),
        ~p"/projects/#{project}/w/#{workflow}?#{[a: run, s: job, m: "expand"]}",
        on_error: :raise
      )

    {high_priority_view, low_priority_view}
  end

  defp restore_listed(%{type: :http_request} = dataclip, body, request) do
    dataclip
    |> Map.put(:body, %{"data" => body, "request" => request})
    |> Map.put(:request, nil)
  end

  defp restore_listed(dataclip, body, _request) do
    dataclip
    |> Map.put(:body, body)
    |> Map.put(:request, nil)
  end

  describe "collaborative editor toggle" do
    setup :create_workflow

    test "shows collaborative editor toggle when experimental features enabled",
         %{
           conn: conn,
           user: user,
           project: project,
           workflow: workflow
         } do
      # Enable experimental features for the user
      user_with_experimental =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      {:ok, view, html} =
        conn
        |> log_in_user(user_with_experimental)
        |> live(~p"/projects/#{project.id}/w/#{workflow.id}")

      # Should show the beaker icon toggle
      assert has_element?(
               view,
               "a[aria-label*='collaborative editor (experimental)']"
             )

      # Should have correct navigation link
      assert has_element?(
               view,
               "a[href='/projects/#{project.id}/w/#{workflow.id}/collaborate']"
             )

      # Should have beaker icon
      assert html =~ "hero-beaker"
    end

    test "hides collaborative editor toggle when experimental features disabled",
         %{
           conn: conn,
           project: project,
           workflow: workflow
         } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      # Should not show the toggle
      refute has_element?(
               view,
               "a[aria-label*='collaborative editor (experimental)']"
             )
    end

    test "hides collaborative editor toggle on non-latest snapshots", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow,
      snapshot: snapshot
    } do
      # Enable experimental features for the user
      user_with_experimental =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      # Create a new snapshot to make the original non-latest
      job_attrs =
        workflow.jobs |> Enum.map(&%{id: &1.id, name: &1.name <> " updated"})

      {:ok, _updated_workflow} =
        Workflows.change_workflow(workflow, %{jobs: job_attrs})
        |> Workflows.save_workflow(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_experimental)
        |> live(
          ~p"/projects/#{project.id}/w/#{workflow.id}?v=#{snapshot.lock_version}"
        )

      # Should not show the toggle for non-latest snapshots
      refute has_element?(
               view,
               "a[aria-label*='collaborative editor (experimental)']"
             )
    end

    test "shows collaborative editor toggle only on latest snapshots with experimental features",
         %{
           conn: conn,
           user: user,
           project: project,
           workflow: workflow
         } do
      # Enable experimental features
      user_with_experimental =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_experimental)
        |> live(~p"/projects/#{project.id}/w/#{workflow.id}")

      # Should show toggle on latest version
      assert has_element?(
               view,
               "a[aria-label*='collaborative editor (experimental)']"
             )
    end

    test "navigates to collaborative editor when toggle clicked", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      # Enable experimental features
      user_with_experimental =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_experimental)
        |> live(~p"/projects/#{project.id}/w/#{workflow.id}")

      # Click the collaborative editor toggle
      view
      |> element("a[aria-label*='collaborative editor (experimental)']")
      |> render_click()

      # Should navigate to collaborative editor route
      assert_redirect(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}/collaborate"
      )
    end

    test "toggle has correct styling and accessibility", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      # Enable experimental features
      user_with_experimental =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_experimental)
        |> live(~p"/projects/#{project.id}/w/#{workflow.id}")

      toggle_element =
        view
        |> element("a[aria-label*='collaborative editor (experimental)']")

      toggle_html = render(toggle_element)

      # Check styling classes
      assert toggle_html =~ "text-primary-600"
      assert toggle_html =~ "hover:text-primary-700"
      assert toggle_html =~ "hover:bg-primary-50"
      assert toggle_html =~ "transition-colors"

      # Check accessibility
      assert toggle_html =~ "aria-label"
      assert toggle_html =~ "collaborative editor (experimental)"

      # Check icon presence
      assert toggle_html =~ "hero-beaker"
    end

    test "preserves existing experimental features preferences", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      # Set up user with experimental features and other preferences
      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{
            "experimental_features" => true,
            "existing_pref" => "value",
            "another_setting" => false
          }
        })
        |> Repo.update!()

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/projects/#{project.id}/w/#{workflow.id}")

      # Should show toggle
      assert has_element?(
               view,
               "a[aria-label*='collaborative editor (experimental)']"
             )

      # Verify all preferences are preserved
      updated_user = Repo.reload(user_with_prefs)
      assert updated_user.preferences["experimental_features"] == true
      assert updated_user.preferences["existing_pref"] == "value"
      assert updated_user.preferences["another_setting"] == false
    end

    test "shows collaborative editor toggle when creating new workflow with experimental features",
         %{
           conn: conn,
           user: user,
           project: project
         } do
      # Enable experimental features
      user_with_experimental =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      {:ok, view, html} =
        conn
        |> log_in_user(user_with_experimental)
        |> live(~p"/projects/#{project.id}/w/new")

      # Should show the beaker icon toggle even on new workflow page
      assert has_element?(
               view,
               "a[aria-label*='collaborative editor (experimental)']"
             )

      # Should have correct navigation link to new workflow collaborative editor
      assert has_element?(
               view,
               "a[href='/projects/#{project.id}/w/new/collaborate']"
             )

      # Should have beaker icon
      assert html =~ "hero-beaker"
    end

    test "hides collaborative editor toggle when creating new workflow without experimental features",
         %{
           conn: conn,
           project: project
         } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new")

      # Should not show the toggle without experimental features
      refute has_element?(
               view,
               "a[aria-label*='collaborative editor (experimental)']"
             )
    end

    test "shows collaborative editor toggle in job inspector with experimental features",
         %{
           conn: conn,
           project: project,
           workflow: workflow,
           user: user
         } do
      # Enable experimental features for user
      user
      |> Ecto.Changeset.change(%{
        preferences: %{"experimental_features" => true}
      })
      |> Lightning.Repo.update!()

      job = insert(:job, workflow: workflow, name: "test-job")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job.id}&m=expand&v=#{workflow.lock_version}"
        )

      # Should show beaker icon in job inspector
      assert html =~ "inspector-collaborative-editor-toggle"
      assert html =~ "hero-beaker"
      assert html =~ "collaborative editor (experimental)"
    end

    test "hides collaborative editor toggle in job inspector without experimental features",
         %{
           conn: conn,
           project: project,
           workflow: workflow,
           user: _user
         } do
      job = insert(:job, workflow: workflow, name: "test-job")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job.id}&m=expand&v=#{workflow.lock_version}"
        )

      # Should not show beaker icon in job inspector
      refute html =~ "inspector-collaborative-editor-toggle"
    end
  end

  describe "sandbox indicator banner" do
    test "shows banner when viewing workflow in sandbox project", %{conn: conn} do
      user = insert(:user)
      parent_project = insert(:project, name: "Production Project")

      sandbox =
        insert(:sandbox,
          parent: parent_project,
          name: "test-sandbox",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: sandbox.id)
      job = insert(:job, workflow: workflow, name: "test-job")

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox.id}/w/#{workflow.id}?s=#{job.id}&m=expand&v=#{workflow.lock_version}"
        )

      # Banner only shows in inspector, not on canvas
      assert html =~ "You are currently working in the sandbox"
      assert html =~ sandbox.name
      # No "Switch to" link per Joe's feedback
      refute html =~ "Switch to"
    end

    test "does not show banner when viewing workflow in root project", %{
      conn: conn
    } do
      user = insert(:user)

      project =
        insert(:project,
          name: "Production Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?v=#{workflow.lock_version}"
        )

      refute html =~ "You are currently working in the sandbox"
      refute html =~ "Switch to"
    end

    test "shows correct root project in deeply nested sandbox", %{conn: conn} do
      user = insert(:user)
      root_project = insert(:project, name: "Root Project")

      sandbox_a =
        insert(:sandbox,
          parent: root_project,
          name: "sandbox-a",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      sandbox_b =
        insert(:sandbox,
          parent: sandbox_a,
          name: "sandbox-b",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: sandbox_b.id)
      job = insert(:job, workflow: workflow, name: "test-job")

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox_b.id}/w/#{workflow.id}?s=#{job.id}&m=expand&v=#{workflow.lock_version}"
        )

      # Banner shows in inspector with current sandbox name
      assert html =~ "You are currently working in the sandbox"
      assert html =~ sandbox_b.name
      # No "Switch to" link per Joe's feedback
      refute html =~ "Switch to"
    end

    test "shows banner in job inspector when editing job in sandbox", %{
      conn: conn
    } do
      user = insert(:user)
      parent_project = insert(:project, name: "Production Project")

      sandbox =
        insert(:sandbox,
          parent: parent_project,
          name: "test-sandbox",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: sandbox.id)
      job = insert(:job, workflow: workflow, name: "test-job")

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox.id}/w/#{workflow.id}?s=#{job.id}&m=expand&v=#{workflow.lock_version}"
        )

      assert html =~ "You are currently working in the sandbox"
      assert html =~ sandbox.name
      # No "Switch to" link per Joe's feedback
      refute html =~ "Switch to"
    end

    test "does not show banner in job inspector when editing job in root project",
         %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          name: "Production Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      job = insert(:job, workflow: workflow, name: "test-job")

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job.id}&m=expand&v=#{workflow.lock_version}"
        )

      refute html =~ "You are currently working in the sandbox"
      refute html =~ "Switch to"
    end

    test "shows env chip on canvas when project has env", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          name: "Production Project",
          env: "production",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?v=#{workflow.lock_version}"
        )

      assert html =~ "canvas-project-env"
      assert html =~ "production"
      assert html =~ "Project environment is production"
    end

    test "shows env chip in inspector when project has env", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          name: "Production Project",
          env: "staging",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = workflow_fixture(project_id: project.id)
      job = insert(:job, workflow: workflow, name: "test-job")

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job.id}&m=expand&v=#{workflow.lock_version}"
        )

      assert html =~ "inspector-project-env"
      assert html =~ "staging"
      assert html =~ "Project environment is staging"
    end
  end

  defp stub_apollo_unavailable(_context) do
    stub(Lightning.MockConfig, :apollo, fn key ->
      case key do
        :endpoint -> "http://localhost:3000"
        :ai_assistant_api_key -> "test_api_key"
      end
    end)

    stub(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
      {:error, :econnrefused}
    end)

    :ok
  end
end
