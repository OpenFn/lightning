defmodule Lightning.WorkflowLive.Helpers do
  @moduledoc false
  import Phoenix.LiveViewTest
  import Lightning.Factories
  import ExUnit.Assertions

  # Interaction Helpers

  def select_job(view, job) do
    view
    |> render_patch("?s=#{job.id}")
  end

  def click_edit(view, job) do
    view
    |> element("#job-pane-#{job.id} a[href*='m=expand']")
    |> render_click()
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

  def add_node_from(view, _node) do
    # TODO: how should we add nodes, we probably should be using the json patch
    # hooks/events here.
    view
    |> editor_element()
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

  def job_panel_element(view, job) do
    view |> element("#job-pane-#{job.id}")
  end

  def job_edit_view(view, job) do
    view |> element("#job-edit-view-#{job.id}")
  end

  def workflow_card(view, workflow) do
    view |> element("#workflow-card-#{workflow.id}", workflow.name)
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

    %{workflow: workflow |> Lightning.Repo.preload([:jobs, :triggers, :edges])}
  end
end
