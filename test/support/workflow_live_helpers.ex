defmodule Lightning.WorkflowLive.Helpers do
  @moduledoc false
  import Phoenix.LiveViewTest
  import Lightning.Factories
  import ExUnit.Assertions

  alias Lightning.Workflows.Job

  # Interaction Helpers

  def select_node(view, node) do
    view
    |> render_patch("?s=#{node.id}")
  end

  def select_first_job(view) do
    job =
      :sys.get_state(view.pid).socket.assigns.changeset
      |> Ecto.Changeset.get_assoc(:jobs, :struct)
      |> List.first()

    {job, 0, view |> select_node(job)}
  end

  def select_trigger(view) do
    trigger =
      :sys.get_state(view.pid).socket.assigns.changeset
      |> Ecto.Changeset.get_assoc(:triggers, :struct)
      |> List.first()

    {trigger, 0, view |> select_node(trigger)}
  end

  def click_edit(view, job) do
    view
    |> element("#job-pane-#{job.id} a[href*='m=expand']")
    |> render_click()
  end

  def click_save(view) do
    view
    |> element("#workflow-form")
    |> render_submit()
  end

  def click_delete_job(view, job) do
    view
    |> delete_job_button(job)
    |> render_click()
  end

  def click_close_error_flash(view) do
    view |> render_click("lv:clear-flash", %{key: "error"})

    refute view
           |> has_element?(
             "div[phx-click='lv:clear-flash'][phx-value-key='error']"
           )
  end

  def click_workflow_card(view, workflow) do
    view |> workflow_card(workflow) |> render_click()
  end

  def click_delete_workflow(view, workflow) do
    view |> delete_workflow_link(workflow) |> render_click()
  end

  def click_create_workflow(view) do
    link =
      view
      |> element("a[href*='/w/new']", "Create new workflow")

    assert has_element?(link)

    link |> render_click()
  end

  def change_editor_text(view, text) do
    view
    |> element("[phx-hook='JobEditor']")
    |> render_hook(:job_body_changed, %{source: text})
  end

  @doc """
  These helpers are used to force events on the workflow form.
  The buttons should be disabled, but a user could still force a save
  by sending a hand-crafted message via the socket.
  """
  def force_event(view, :save) do
    view |> render_submit(:save, %{workflow: %{name: "New Name"}})
  end

  def force_event(view, :form_changed) do
    view.pid |> send({"form_changed", %{"workflow" => %{"name" => "New Name"}}})
    render(view)
  end

  def force_event(view, :validate) do
    view
    |> render_click("validate", %{workflow: %{name: "New Name"}})
  end

  def force_event(view, :delete_node, job) do
    view
    |> render_click("delete_node", %{id: job.id})
  end

  @doc """
  This helper is used to fill in the form fields for a given job.
  Internally it looks up the index of the job in the workflow_params
  which is what the form uses to identify the job.

  If the job or it's corresponding form elements are not found,
  an assertian error is raised.

  **NOTE** this helper _only_ fills in fields available on the job panel, fields
  such as the job's body are not available here.

  ## Examples

      view
      |> fill_job_fields(%{id: job.id}, %{name: "My Job"})
  """
  def fill_job_fields(view, job, attrs) do
    job_id = Map.get(job, :id)

    idx = get_index_of_job(view, job)

    assert element(view, "[name^='workflow[jobs][#{idx}]']") |> has_element?(),
           "can find the job form for #{job_id}, got an index of #{inspect(idx)}"

    view
    |> form("#workflow-form", %{
      "workflow" => %{"jobs" => %{to_string(idx) => attrs}}
    })
    |> render_change()
  end

  def add_node_from(view, _node) do
    # TODO: how should we add nodes, we probably should be using the json patch
    # hooks/events here.
    view
    |> editor_element()
  end

  def fill_workflow_name(view, name) do
    view
    |> element("#workflow_name_form")
    |> render_change(%{"workflow" => %{"name" => name}})
  end

  # Internal Interaction Helpers

  @doc """
  This is a helper for interacting with the editor. It similates changes
  made to the Zustand store by the diagram component.
  """
  def push_patches_to_view(view, patches) do
    view
    |> editor_element()
    |> render_hook("push-change", %{patches: patches})
  end

  def add_job_patch(name \\ "") do
    Jsonpatch.diff(
      %{jobs: []},
      %{jobs: [%{id: Ecto.UUID.generate(), name: name}]}
    )
    |> Jsonpatch.Mapper.to_map()
    |> List.first()
    |> Lightning.Helpers.json_safe()
  end

  def get_index_of_job(view, job) do
    :sys.get_state(view.pid).socket.assigns.workflow_params
    |> Map.get("jobs")
    |> Enum.find_index(fn j -> j["id"] == job.id end)
  end

  def get_index_of_edge(view, edge) do
    :sys.get_state(view.pid).socket.assigns.workflow_params
    |> Map.get("edges")
    |> Enum.find_index(fn e -> e["id"] == edge.id end)
  end

  def get_workflow_params(view) do
    :sys.get_state(view.pid).socket.assigns.workflow_params
  end

  @doc """
  This helper replicates the data sent to the server when a new workflow is
  created, and the WorkflowDiagram component is mounted and determines the
  initial state of the diagram.

  i.e. the initial state of a new workflow is essentially an empty map, the
  diagram component then adds some initial nodes and edges to the diagram.
  """
  def initial_workflow_patchset(project) do
    job_id = Ecto.UUID.generate()
    trigger_id = Ecto.UUID.generate()

    Jsonpatch.diff(
      %{
        "edges" => [],
        "errors" => %{"name" => ["can't be blank"]},
        "jobs" => [],
        "name" => "",
        "project_id" => project.id,
        "triggers" => []
      },
      %{
        "triggers" => [%{"id" => trigger_id}],
        "jobs" => [%{"id" => job_id}],
        "edges" => [
          %{
            "id" => Ecto.UUID.generate(),
            "source_trigger_id" => trigger_id,
            "condition" => :always,
            "target_job_id" => job_id
          }
        ],
        "name" => "",
        "project_id" => project.id
      }
    )
    |> Jsonpatch.Mapper.to_map()
    |> Enum.map(&Lightning.Helpers.json_safe/1)
  end

  # Assertion Helpers

  def job_form_has_error(view, job, field, error) do
    idx = get_index_of_job(view, job)

    view
    |> element(
      ~s{#workflow_jobs_#{idx}_#{field} + [data-tag="error_message"]},
      error
    )
    |> has_element?()
  end

  def has_pending_changes(view) do
    view |> element("[data-is-dirty]") |> has_element?()
  end

  def save_is_disabled?(view) do
    view
    |> element("button[type='submit'][form='workflow-form'][disabled]")
    |> has_element?()
  end

  def input_is_disabled?(view, %Job{} = job, field) do
    idx = get_index_of_job(view, job)

    view
    |> input_is_disabled?(
      "#job-pane-#{job.id} [name='workflow[jobs][#{idx}][#{field}]']"
    )
  end

  def input_is_disabled?(view, selector) do
    view
    |> element("#{selector}[disabled]")
    |> has_element?()
  end

  def delete_job_button_is_disabled?(view, %Job{} = job) do
    delete_job_button(view, job)
    |> Map.update!(:selector, &(&1 <> "[disabled]"))
    |> has_element?()
  end

  def has_workflow_edit_container?(view, workflow) do
    view
    |> element("#workflow-edit-#{workflow.id}")
    |> has_element?()
  end

  def has_link?(view, path, text_filter \\ nil) do
    view
    |> find_a_tag(path, text_filter)
    |> has_element?()
  end

  def has_workflow_card?(view, workflow) do
    view |> workflow_card(workflow) |> has_element?()
  end

  # Element Helpers

  def editor_element(view) do
    view |> element("div[phx-hook=WorkflowEditor]")
  end

  def selected_adaptor_version_element(view, job) do
    view |> element("#job-pane-#{job.id} #adaptor-version option[selected]")
  end

  def selected_credential(view, job) do
    view
    |> element("#job-pane-#{job.id} select[id$=credential_id] option[selected]")
    |> render()
  end

  def job_panel_element(view, job) do
    view |> element("#job-pane-#{job.id}")
  end

  def job_edit_view(view, job) do
    view |> element("#job-edit-view-#{job.id}")
  end

  def workflow_card(view, workflow) do
    view |> element("#workflow-card-#{workflow.id}", workflow.name)
  end

  def delete_job_button(view, %Job{} = job) do
    view
    |> element("#job-pane-#{job.id} button[phx-click='delete_node']")
  end

  def delete_workflow_link(view, workflow) do
    view
    |> element("[phx-click='delete_workflow'][phx-value-id='#{workflow.id}']")
  end

  def has_delete_workflow_link?(view, workflow) do
    view
    |> delete_workflow_link(workflow)
    |> has_element?()
  end

  def find_a_tag(view, path, text_filter \\ nil) do
    view
    |> element("a[href='#{path}']", text_filter)
  end

  # Model & Factory Helpers

  def create_workflow(%{project: project}) do
    trigger = build(:trigger, type: :webhook)

    job_1 =
      build(:job,
        body: ~s[fn(state => { return {...state, extra: "data"} })],
        name: "First Job"
      )

    job_2 =
      build(:job,
        body: ~s[fn(state => { return {...state, extra: "data"} })],
        name: "Second Job"
      )

    workflow =
      build(:workflow, project: project)
      |> with_job(job_1)
      |> with_trigger(trigger)
      |> with_edge({trigger, job_1}, %{condition: :always})
      |> with_job(job_2)
      |> with_edge({job_1, job_2}, %{condition: :on_job_success})
      |> insert()

    %{workflow: workflow |> Lightning.Repo.preload([:jobs, :triggers, :edges])}
  end
end
