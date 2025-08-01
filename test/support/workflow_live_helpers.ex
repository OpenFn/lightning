defmodule Lightning.WorkflowLive.Helpers do
  @moduledoc false
  import Phoenix.LiveViewTest
  import Lightning.Factories
  import ExUnit.Assertions

  alias Lightning.Workflows
  alias Lightning.Projects.Project
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Edge

  # Interaction Helpers

  def select_node(view, node, version \\ nil) do
    query_string =
      if version, do: "?s=#{node.id}&v=#{version}", else: "?s=#{node.id}"

    view
    |> render_patch(query_string)
  end

  def select_first_job(view) do
    changeset = :sys.get_state(view.pid).socket.assigns.changeset

    job =
      changeset
      |> Ecto.Changeset.get_assoc(:jobs, :struct)
      |> List.first()

    version = Ecto.Changeset.get_field(changeset, :lock_version)

    {job, 0, view |> select_node(job, version)}
  end

  def select_trigger(view) do
    changeset = :sys.get_state(view.pid).socket.assigns.changeset

    trigger =
      changeset
      |> Ecto.Changeset.get_assoc(:triggers, :struct)
      |> List.first()

    version = Ecto.Changeset.get_field(changeset, :lock_version)

    {trigger, 0, view |> select_node(trigger, version)}
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

  @doc """
  This helper is used to trigger the save event on the workflow form.

  This is the same as pressing `Ctrl+S` or `Cmd+S`,
  note that it doesn't send any changes to the server, it just triggers the event.
  """
  def trigger_save(view, params \\ %{}) do
    view |> render_hook("save", params)
  end

  def click_delete_job(view, job) do
    view
    |> delete_job_button(job)
    |> render_click()
  end

  def click_delete_edge(view, trigger) do
    view
    |> delete_edge_button(trigger)
    |> render_click()
  end

  def click_close_job_edit_view(view) do
    close_btn =
      view
      |> element("a[id^='close-job-edit-view']")

    assert has_element?(close_btn)

    close_btn |> render_click()
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

  def change_adaptor(view, job, adaptor) do
    {job, adaptor}

    view
    |> element("#job-pane-#{job.id} select[name='adaptor_picker[adaptor_name]']")
    |> render_change(%{
      "adaptor_picker" => %{"adaptor_name" => adaptor}
    })
  end

  def change_adaptor_version(view, version) do
    idx = get_index_of_job(view)

    view
    |> form("#workflow-form", %{
      "workflow" => %{"jobs" => %{"#{idx}" => %{"adaptor" => version}}}
    })
    |> render_change()
  end

  def change_credential(view, job, credential) do
    idx = get_index_of_job(view, job)

    case credential do
      %Lightning.Projects.ProjectCredential{} ->
        view
        |> form("#workflow-form")
        |> render_change(%{
          "workflow" => %{
            "jobs" => %{
              "#{idx}" => %{
                "project_credential_id" => credential.id,
                "keychain_credential_id" => ""
              }
            }
          }
        })

      %Lightning.Credentials.KeychainCredential{} ->
        view
        |> form("#workflow-form")
        |> render_change(%{
          "workflow" => %{
            "jobs" => %{
              "#{idx}" => %{
                "keychain_credential_id" => credential.id,
                "project_credential_id" => ""
              }
            }
          }
        })
    end
  end

  @doc """
  Change the text of the selected job's body, just like the React component
  does.
  """
  def change_editor_text(view, text) do
    idx = get_index_of_job(view)

    view
    |> element("[phx-hook='ReactComponent'][data-react-name='JobEditor']")
    |> render_hook("push-change", %{
      patches: [%{op: "replace", path: "/jobs/#{idx}/body", value: text}]
    })
  end

  def close_job_edit_view(view, job) do
    view
    |> element("a#close-job-edit-view-#{job.id}")
    |> render_click()
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
    view.pid |> send({:form_changed, %{"workflow" => %{"name" => "New Name"}}})
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

  def force_event(view, :delete_edge, edge) do
    view
    |> render_click("delete_edge", %{id: edge.id})
  end

  def force_event(view, :manual_run_submit, params) do
    view
    |> render_click("manual_run_submit", %{"manual" => params})
  end

  def force_event(view, :switch_workflow_version, type) do
    view |> render_click("switch-version", %{"type" => type})
  end

  def force_event(view, :rerun, run_id, step_id) do
    view
    |> render_click("rerun", %{"run_id" => run_id, "step_id" => step_id})
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
    |> element("#workflow-form")
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

  def select_template(view, template_id) do
    view
    |> form("#choose-workflow-template-form", %{template_id: template_id})
    |> render_change()
  end

  def add_job_patch(name \\ "", id \\ Ecto.UUID.generate()) do
    Jsonpatch.diff(
      %{jobs: []},
      %{jobs: [%{id: id, name: name}]}
    )
    |> List.first()
    |> Lightning.Helpers.json_safe()
  end

  def get_index_of_job(view, job \\ nil) do
    job_id =
      (job && job.id) || :sys.get_state(view.pid).socket.assigns.selected_job.id

    :sys.get_state(view.pid).socket.assigns.workflow_params
    |> Map.get("jobs")
    |> Enum.find_index(fn j -> j["id"] == job_id end)
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
            "condition_type" => :always,
            "target_job_id" => job_id
          }
        ],
        "name" => "",
        "project_id" => project.id
      }
    )
    |> Enum.map(&Lightning.Helpers.json_safe/1)
  end

  # Assertion Helpers

  def job_form_has_error(view, job, field, error) do
    idx = get_index_of_job(view, job)

    view
    |> element(
      ~s{div[phx-feedback-for="workflow[jobs][#{idx}][#{field}]"] .error-space [data-tag="error_message"]},
      error
    )
    |> has_element?()
  end

  def has_pending_changes(view) do
    view |> element("[data-is-dirty]") |> has_element?()
  end

  # Really don't like that we don't have _any_ submit buttons on the page
  # at this exact moment.
  # We're relying entirely on the WorkflowStore and phx-change events to update
  # the state of the form in the LiveView.
  def save_is_disabled?(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("button")
    |> Enum.filter(fn {_, _attrs, children} ->
      children |> Floki.text() |> String.contains?("Save")
    end)
    |> Enum.all?(fn {_, attrs, _} ->
      {"disabled", "disabled"} in attrs
    end)
  end

  def input_is_disabled?(view, %Job{} = job, field) do
    idx = get_index_of_job(view, job)

    selector =
      case field do
        "project_credential_id" ->
          "#job-pane-#{job.id} [name='credential_selector']"

        _ ->
          "#job-pane-#{job.id} [name='workflow[jobs][#{idx}][#{field}]']"
      end

    view
    |> input_is_disabled?(selector)
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

  def delete_edge_button_is_disabled?(view, %Edge{} = edge) do
    delete_edge_button(view, edge)
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

  def has_history_link_pattern?(
        html,
        %Project{id: project_id},
        pattern,
        text \\ ""
      )
      when is_binary(html) do
    pattern = String.replace(pattern, "[", "\\[") |> String.replace("]", "\\]")

    Regex.match?(
      ~r{<a href="/projects/#{project_id}/history\?.*#{pattern}.*#{text}.*</a>}s,
      html
    )
  end

  def has_workflow_card?(view, workflow) do
    view |> workflow_card(workflow) |> has_element?()
  end

  # Element Helpers

  def editor_element(view) do
    view |> element("[phx-hook=ReactComponent][data-react-name=WorkflowEditor]")
  end

  def selected_adaptor_version_element(view, job) do
    view |> element("#job-pane-#{job.id} #adaptor-version option[selected]")
  end

  def credential_options(view, job \\ nil) do
    job_id =
      (job && job.id) || :sys.get_state(view.pid).socket.assigns.selected_job.id

    view
    |> element("#job-pane-#{job_id} select[name='credential_selector']")
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("option")
    |> Enum.map(fn option ->
      %{
        text: Floki.text(option),
        value: Floki.attribute(option, "value") |> List.first()
      }
    end)
  end

  def selected_credential_name(view, job \\ nil) do
    job_id =
      (job && job.id) || :sys.get_state(view.pid).socket.assigns.selected_job.id

    # Check hidden field value since the JavaScript populates it
    credential_id =
      ["project_credential_id", "keychain_credential_id"]
      |> Enum.map(fn key ->
        view
        |> element("#job-pane-#{job_id} input[type='hidden'][name$='[#{key}]']")
        |> render()
        |> Floki.parse_document!()
        |> Floki.attribute("value")
        |> List.first()
      end)
      |> Enum.find(& &1)

    if credential_id do
      # Find the option with this value and return its html
      view
      |> element("#job-pane-#{job_id} select[name='credential_selector']")
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("option[value='#{credential_id}']")
      |> Floki.text()
    else
      ""
    end
  end

  def job_panel_element(view, job) do
    view |> element("#job-pane-#{job.id}")
  end

  def job_edit_view(view, job) do
    view |> element("#job-edit-view-#{job.id}")
  end

  def workflow_card(view, workflow) do
    element(view, "#workflow-#{workflow.id}")
  end

  def delete_job_button(view, %Job{} = job) do
    view
    |> element("#job-pane-#{job.id} button[phx-click='delete_node']")
  end

  def delete_edge_button(view, %Edge{} = edge) do
    view
    |> element("#edge-pane-#{edge.id} button[phx-click='delete_edge']")
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

  @doc """
  Returns the attributes and inner HTML of a given element.
  """
  def get_attrs_and_inner_html(element) do
    element
    |> render()
    |> Floki.parse_fragment!()
    |> then(fn elements ->
      case elements do
        [element] -> element
        _ -> raise "Expected exactly one element, but got #{length(elements)}"
      end
    end)
    |> then(fn {_tag, attrs, inner_html} ->
      {Map.new(attrs), inner_html |> Enum.join()}
    end)
  end

  @doc """
  Decodes the inner HTML of a React component.
  To be used with `get_attrs_and_inner_html/1`.

  ## Examples

      view
      |> dataclip_viewer("step-output-dataclip-viewer")
      |> get_attrs_and_inner_html()
      |> decode_inner_json()

      # =>
      # {
      #   %{"data-react-id" => "step-output-dataclip-viewer"},
      #   %{"body" => "..."}
      # }
  """
  def decode_inner_json({attrs, inner_html}) do
    {attrs, inner_html |> Jason.decode!()}
  end

  def dataclip_viewer(view, id) do
    view
    |> element(
      "script[phx-hook='ReactComponent'][data-react-name='DataclipViewer'][id='#{id}']"
    )
  end

  def job_editor(view, id \\ 1) do
    view
    |> element(
      "script[phx-hook='ReactComponent'][data-react-name='JobEditor'][id='JobEditor-#{id}']"
    )
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
      |> with_edge({trigger, job_1}, %{condition_type: :always})
      |> with_job(job_2)
      |> with_edge({job_1, job_2}, %{condition_type: :on_job_success})
      |> insert()

    {:ok, snapshot} = Workflows.Snapshot.create(workflow)

    %{
      workflow: workflow |> Lightning.Repo.preload([:jobs, :triggers, :edges]),
      snapshot: snapshot
    }
  end
end
