defmodule LightningWeb.WorkflowLive.EditTest do
  alias Lightning.Repo
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Lightning.WorkflowLive.Helpers
  import Lightning.WorkflowsFixtures
  import Lightning.JobsFixtures
  import Lightning.Factories
  import Ecto.Query

  alias LightningWeb.CredentialLiveHelpers
  alias Lightning.Workflows.Workflow

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "New credential from project context " do
    setup %{project: project} do
      %{job: job} = workflow_job_fixture(project_id: project.id)
      %{job: job}
    end

    test "open credential modal from the job inspector (edit_job)", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{job.workflow_id}?s=#{job.id}")

      assert has_element?(view, "#job-pane-#{job.id}")

      assert has_element?(view, "#credential-type-picker")
      view |> CredentialLiveHelpers.select_credential_type("http")
      view |> CredentialLiveHelpers.click_continue()

      refute has_element?(view, "#project_list")
    end

    test "create new credential from job inspector and update the job form", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{job.workflow_id}?s=#{job.id}")

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
                "body" => ["This field can't be blank."],
                "name" => ["This field can't be blank."]
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
                  "body" => ["This field can't be blank."],
                  "name" => ["This field can't be blank."]
                }
              ]
            }
          ]
        }
      )
    end

    @tag role: :editor
    test "creating a new workflow", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      assert view |> push_patches_to_view(initial_workflow_patchset(project))

      workflow_name = view |> get_workflow_params() |> Map.get("name")

      assert workflow_name == ""

      assert view |> element("#workflow_name_form") |> render() =~ workflow_name

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

      refute view |> save_is_disabled?()

      assert view |> has_pending_changes()

      view |> click_save()

      assert %{id: workflow_id} =
               Lightning.Repo.one(
                 from w in Workflow,
                   where:
                     w.project_id == ^project.id and
                       w.name ==
                         ^workflow_name
               )

      #
      %{"info" => "Workflow saved"} =
        assert_redirected(view, ~p"/projects/#{project.id}/w/#{workflow_id}")
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

    test "click on pencil icon activates workflow name edit mode", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      another_workflow =
        workflow_fixture(name: "A random workflow", project_id: project.id)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      assert view |> has_element?(~s(input[name="workflow[name]"]))

      assert view
             |> form("#workflow_name_form", %{"workflow" => %{"name" => ""}})
             |> render_change() =~ "can&#39;t be blank"

      html =
        view
        |> form("#workflow_name_form", %{
          "workflow" => %{"name" => another_workflow.name}
        })
        |> render_submit()

      assert html =~ "a workflow with this name already exists in this project."
      assert html =~ "Workflow could not be saved"

      assert view
             |> form("#workflow_name_form", %{
               "workflow" => %{"name" => "some new name"}
             })
             |> render_submit() =~ "Workflow saved"
    end

    test "renders error message when a job has an empty body", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      job = workflow.jobs |> Enum.at(1)

      view |> select_node(job)

      view |> click_edit(job)

      view |> change_editor_text("some body")

      refute view |> render() =~
               "The job can&#39;t be blank"

      view |> change_editor_text("")

      assert view |> render() =~
               "The job can&#39;t be blank"
    end

    test "allows editing job name", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      assert view |> page_title() =~ workflow.name

      view |> fill_workflow_name("")

      job_2 = workflow.jobs |> Enum.at(1)

      view |> select_node(job_2)
      view |> fill_job_fields(job_2, %{name: ""})

      assert view |> job_form_has_error(job_2, "name", "can't be blank")
      assert view |> save_is_disabled?()

      new_job_name = "My Other Job"

      assert view |> fill_job_fields(job_2, %{name: new_job_name}) =~
               new_job_name

      assert view |> save_is_disabled?()
    end

    test "opens edge Path form and saves the JS expression", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      form_html = view |> select_node(Enum.at(workflow.jobs, 0))

      assert form_html =~ "Job Name"
      refute form_html =~ "Path"

      form_html = view |> select_node(Enum.at(workflow.edges, 0))

      assert form_html =~ "Path"

      assert form_html =~
               ~S[<option selected="selected" value="always">Always</option><option value="js_expression">Matches a Javascript Expression</option></select>]

      edge_on_edit = Enum.at(workflow.edges, 1)
      form_html = view |> select_node(edge_on_edit)

      assert form_html =~
               ~S[<option selected="selected" value="on_job_success">On Success</option>]

      refute form_html =~ "Condition Label"

      form_html =
        view
        |> form("#workflow-form", %{
          "workflow" => %{
            "edges" => %{"1" => %{"condition_type" => "js_expression"}}
          }
        })
        |> render_change()

      assert form_html =~ "Condition Label"

      assert form_html =~
               ~S[<option selected="selected" value="js_expression">Matches a Javascript Expression</option>]

      view
      |> form("#workflow-form", %{
        "workflow" => %{
          "edges" => %{
            "1" => %{
              "condition_label" => "My JS Expression",
              "js_expression_body" => "state.data.field === 33"
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
                   js_expression_body: "state.data.field === 33"
                 }),
                 :updated_at
               )
    end

    @tag role: :editor
    test "can delete a job", %{conn: conn, project: project, workflow: workflow} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/w/#{workflow}")

      [job_1, job_2] = workflow.jobs
      view |> select_node(job_1)

      assert view |> delete_job_button_is_disabled?(job_1)

      # Test that the delete event doesn't work even if the button is disabled.
      assert view |> force_event(:delete_node, job_1) =~
               "Delete all descendant jobs first."

      view |> select_node(job_2)
      assert_patched(view, ~p"/projects/#{project}/w/#{workflow}?s=#{job_2}")

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
    test "", %{
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

      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/w/#{workflow}")

      view |> select_node(job)

      assert view |> delete_job_button_is_disabled?(job)

      assert view |> force_event(:delete_node, job) =~
               "You can&#39;t delete the only job in a workflow."
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

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}?s=#{job_a}")

      assert view |> delete_job_button_is_disabled?(job_a)

      assert html =~
               "You can&#39;t delete a job that has downstream jobs flowing from it."

      assert view |> force_event(:delete_node, job_a) =~
               "Delete all descendant jobs first"

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}?s=#{job_b}")

      assert view |> delete_job_button_is_disabled?(job_b)

      assert html =~
               "You can&#39;t delete a job that has downstream jobs flowing from it."

      assert view |> force_event(:delete_node, job_a) =~
               "Delete all descendant jobs first"
    end

    @tag role: :viewer
    test "viewers can't edit existing jobs", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      view |> select_node(workflow.triggers |> Enum.at(0))

      assert view |> input_is_disabled?("[name='workflow[triggers][0][type]']")

      view |> select_node(workflow.edges |> Enum.at(0))

      assert view
             |> input_is_disabled?("[name='workflow[edges][0][condition_type]']")

      assert view |> save_is_disabled?()
      job_1 = workflow.jobs |> Enum.at(0)

      view |> select_node(job_1)

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
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{edge.id}")

      idx = get_index_of_edge(view, edge)

      assert html =~ "Disable this path"

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

      assert view
             |> element("#workflow_edges_#{idx}_enabled[checked]")
             |> has_element?()
    end
  end
end
