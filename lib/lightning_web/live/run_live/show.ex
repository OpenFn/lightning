defmodule LightningWeb.RunLive.Show do
  @moduledoc """
  One run: its details, its steps, the selected step's input and output, and
  its log. The design system's page draws it from props; this LiveView loads
  the run, follows its events, streams the log lines to the page as they
  arrive, and answers Cancel and the log level.
  """
  use LightningWeb, :live_view
  use LightningWeb.RunLive.Streaming, chunk_size: 100

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias LightningWeb.RunLive.CancelHelper
  alias Phoenix.LiveView.AsyncResult

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :ensure_run_belongs_to_project}
  on_mount {LightningWeb.Hooks, :check_limits}

  @log_levels ~w(debug info warn error)

  @impl true
  def render(assigns) do
    ~H"""
    <.design_system_page
      name="RunShowPage"
      props={page_props(assigns)}
      banner={assigns[:banner]}
      current_user={@current_user}
    />
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    %{current_user: user, project_user: project_user, project: project} =
      socket.assigns

    can_edit_data_retention =
      Permissions.can?(ProjectUsers, :edit_data_retention, user, project_user)

    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       page_title: "Run",
       id: id,
       selected_step_id: nil,
       selected_step: nil,
       steps: [],
       input_dataclip: nil,
       output_dataclip: nil,
       run: AsyncResult.loading(),
       log_lines: AsyncResult.loading(),
       logs_wanted?: false,
       experimental_features:
         Lightning.Accounts.experimental_features_enabled?(user),
       can_run_workflow:
         Permissions.can?(ProjectUsers, :run_workflow, user, project),
       can_edit_data_retention: can_edit_data_retention,
       # The emails are shown only to someone who cannot change the policy,
       # on a wiped dataclip; nobody else gets them.
       admin_contacts:
         if(can_edit_data_retention,
           do: [],
           else: Projects.list_project_admin_emails(project.id)
         )
     )
     |> get_run_async(id, project.id)}
  end

  # A step id that is not one of this run's steps selects nothing, and shows
  # no dataclip from an earlier selection.
  def handle_steps_change(socket) do
    %{selected_step_id: selected_step_id, steps: steps} = socket.assigns

    case Enum.find(steps, &(&1.id == selected_step_id)) do
      nil ->
        assign(socket,
          selected_step: nil,
          input_dataclip: nil,
          output_dataclip: nil
        )

      selected_step ->
        socket
        |> assign(selected_step: selected_step)
        |> maybe_load_input_dataclip()
        |> maybe_load_output_dataclip()
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    {:noreply, apply_selected_step_id(socket, Map.get(params, "step"))}
  end

  # Cancel acts on the run this page is for, never on an id from the browser.
  @impl true
  def handle_event("cancel_run", _params, socket) do
    %{can_run_workflow: can_run_workflow, id: id, project: project} =
      socket.assigns

    if can_run_workflow do
      case CancelHelper.cancel_run(id, project.id) do
        {:ok, _run} ->
          {:reply, %{}, put_flash(socket, :info, "Run cancelled.")}

        {:error, :not_found} ->
          reply_error(socket, "Run not found.")

        {:error, :not_available} ->
          {:reply, %{},
           put_flash(
             socket,
             :info,
             "Run could not be cancelled — it has already been " <>
               "claimed by a worker."
           )}

        {:error, _} ->
          reply_error(socket, "An error occurred while cancelling.")
      end
    else
      reply_error(socket, "You are not authorized to perform this action.")
    end
  end

  def handle_event("save_log_level", %{"level" => level}, socket)
      when level in @log_levels do
    case Lightning.Accounts.update_user_preference(
           socket.assigns.current_user,
           "desired_log_level",
           level
         ) do
      {:ok, user} -> {:reply, %{}, assign(socket, current_user: user)}
      {:error, _} -> reply_error(socket, "Could not save the log level.")
    end
  end

  def handle_event("save_log_level", _params, socket) do
    reply_error(socket, "Invalid request")
  end

  # The page is listening for log lines: send them, now or once the run has
  # loaded. A page that asks again (a reconnect) gets them again.
  def handle_event("logs_ready", _params, socket) do
    {:reply, %{},
     socket
     |> assign(logs_wanted?: true)
     |> stream_log_lines(@chunk_size)}
  end

  @impl true
  def handle_info(%Lightning.Runs.Events.DataclipUpdated{}, socket) do
    {:noreply, socket}
  end

  # The shape the design system's RunShowPageProps expect, minus the log,
  # which arrives by `push_event` as the lines are read.
  defp page_props(assigns) do
    %{run: run, project: project} = assigns

    %{
      project: %{
        id: project.id,
        parentId: project.parent_id,
        color: project.color
      },
      projectLabel: assigns.project_label,
      runId: assigns.id,
      loading: not run.ok? and is_nil(run.failed),
      run: if(run.ok?, do: run_json(run.result)),
      workflow: workflow_json(assigns[:workflow]),
      steps: Enum.map(assigns.steps, &step_json/1),
      selectedStepId: assigns.selected_step_id,
      inputDataclip: dataclip_json(assigns.input_dataclip),
      outputDataclip: dataclip_json(assigns.output_dataclip),
      logLevel: log_level(assigns.current_user),
      experimentalFeatures: assigns.experimental_features,
      canRunWorkflow: assigns.can_run_workflow,
      canEditDataRetention: assigns.can_edit_data_retention,
      # Named only by a wiped notice, so sent only when one is showing.
      adminContacts:
        if(wiped_showing?(assigns), do: assigns.admin_contacts, else: [])
    }
  end

  defp wiped_showing?(%{selected_step: nil}), do: false

  defp wiped_showing?(%{selected_step: step} = assigns) do
    wiped?(assigns.input_dataclip, step.finished_at, step.input_dataclip_id) or
      wiped?(assigns.output_dataclip, step.finished_at, step.output_dataclip_id)
  end

  defp wiped?(%{wiped_at: %DateTime{}}, _finished_at, _id), do: true
  defp wiped?(nil, %DateTime{}, nil), do: true
  defp wiped?(_dataclip, _finished_at, _id), do: false

  defp run_json(run) do
    %{
      id: run.id,
      workOrderId: run.work_order_id,
      state: run.state,
      startedBy: started_by(run),
      insertedAt: run.inserted_at,
      startedAt: run.started_at,
      finishedAt: run.finished_at,
      finalDataclipId: run.final_dataclip_id,
      snapshot: %{
        id: run.snapshot.id,
        lockVersion: run.snapshot.lock_version,
        insertedAt: run.snapshot.inserted_at
      }
    }
  end

  defp started_by(%{created_by: %{email: email}}), do: email

  defp started_by(%{starting_trigger: %{type: type}}),
    do: String.capitalize(Atom.to_string(type)) <> " trigger"

  defp started_by(_run), do: nil

  defp workflow_json(nil), do: nil

  defp workflow_json(workflow),
    do: %{
      id: workflow.id,
      name: workflow.name,
      lockVersion: workflow.lock_version
    }

  defp step_json(step) do
    %{
      id: step.id,
      jobId: step.job_id,
      jobName: job_name(step),
      exitReason: step.exit_reason,
      errorType: step.error_type,
      startedAt: step.started_at,
      finishedAt: step.finished_at,
      insertedAt: step.inserted_at,
      inputDataclipId: step.input_dataclip_id,
      outputDataclipId: step.output_dataclip_id,
      snapshotLockVersion: step.snapshot.lock_version
    }
  end

  # The job's name as it was in the snapshot the step ran on.
  defp job_name(step) do
    case Enum.find(step.snapshot.jobs, &(&1.id == step.job_id)) do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp dataclip_json(nil), do: nil

  defp dataclip_json(dataclip),
    do: %{id: dataclip.id, wiped: not is_nil(dataclip.wiped_at)}

  defp log_level(user) do
    case Map.get(user.preferences, "desired_log_level") do
      level when level in @log_levels -> level
      _ -> "info"
    end
  end
end
