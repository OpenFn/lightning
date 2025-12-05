defmodule LightningWeb.WorkflowController do
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Runs
  alias Lightning.Workflows
  alias Lightning.WorkOrders
  alias LightningWeb.WorkflowLive.Helpers

  action_fallback LightningWeb.FallbackController

  @doc """
  Create a manual workflow run.

  Body:
  - job_id: Job to start from (required)
  - trigger_id: Trigger to start from (alternative to job_id)
  - dataclip_id: Existing dataclip ID (optional)
  - custom_body: Custom JSON input (optional)

  Note: Either job_id or trigger_id must be provided.
  Either dataclip_id or custom_body can be provided, but not both.
  """
  def create_run(
        conn,
        %{"project_id" => project_id, "workflow_id" => workflow_id} = params
      ) do
    project = Projects.get_project!(project_id)

    workflow =
      Workflows.get_workflow!(workflow_id,
        include: [:jobs, :triggers, :edges]
      )

    current_user = conn.assigns.current_user

    # Authorization checks
    with :ok <- check_permissions(conn, project, workflow),
         {:ok, selected_job} <- get_selected_job(workflow, params),
         {:ok, result} <-
           create_manual_run(
             workflow,
             selected_job,
             params,
             project,
             current_user
           ) do
      %{workorder: workorder} = result
      [run | _] = workorder.runs

      # Get the dataclip for the response
      dataclip = Invocation.get_dataclip_for_run(run.id)

      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          workorder_id: workorder.id,
          run_id: run.id,
          dataclip: dataclip
        }
      })
    end
  end

  defp check_permissions(conn, project, _workflow) do
    current_user = conn.assigns.current_user

    cond do
      not Permissions.can?(
        :project_users,
        :edit_workflow,
        current_user,
        project
      ) ->
        {:error, :forbidden}

      not Permissions.can?(
        :project_users,
        :run_workflow,
        current_user,
        project
      ) ->
        {:error, :forbidden}

      true ->
        :ok
    end
  end

  defp get_selected_job(workflow, %{"job_id" => job_id})
       when not is_nil(job_id) do
    case Enum.find(workflow.jobs, fn j -> j.id == job_id end) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  defp get_selected_job(workflow, %{"trigger_id" => trigger_id})
       when not is_nil(trigger_id) do
    # Find the trigger and get its connected job
    trigger = Enum.find(workflow.triggers, fn t -> t.id == trigger_id end)

    if trigger do
      # Find edge from trigger to job
      edge =
        Enum.find(workflow.edges, fn e ->
          e.source_trigger_id == trigger_id
        end)

      if edge do
        job = Enum.find(workflow.jobs, fn j -> j.id == edge.target_job_id end)
        if job, do: {:ok, job}, else: {:error, :not_found}
      else
        {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  defp get_selected_job(_workflow, _params) do
    {:error, :bad_request}
  end

  defp create_manual_run(workflow, selected_job, params, project, current_user) do
    manual_params = %{
      "dataclip_id" => params["dataclip_id"],
      "body" => params["custom_body"] || "{}"
    }

    Helpers.run_workflow(
      workflow,
      manual_params,
      project: project,
      selected_job: selected_job,
      created_by: current_user
    )
  end

  @doc """
  Get steps for a run filtered by job_id.

  Query params:
  - job_id: Filter steps for a specific job (required)

  Returns the step data including id, input_dataclip_id, and job_id.
  Used by the frontend to determine if a retry is available.
  """
  def get_run_steps(
        conn,
        %{
          "project_id" => project_id,
          "run_id" => run_id,
          "job_id" => job_id
        }
      ) do
    project = Projects.get_project!(project_id)

    with run <- Runs.get(run_id, include: [steps: [], work_order: [:workflow]]),
         :ok <-
           Permissions.can(
             :project_users,
             :access_project,
             conn.assigns.current_user,
             project
           ),
         :ok <-
           verify_run_belongs_to_project(run, project) do
      step =
        run.steps
        |> Enum.find(fn s -> s.job_id == job_id end)

      if step do
        json(conn, %{
          data: %{
            id: step.id,
            input_dataclip_id: step.input_dataclip_id,
            job_id: step.job_id
          }
        })
      else
        conn
        |> put_status(:not_found)
        |> json(%{error: "Step not found for the specified job"})
      end
    end
  end

  def get_run_steps(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: job_id"})
  end

  @doc """
  Retry an existing run from a specific step.

  Body:
  - step_id: The step ID to retry from (required)

  Creates a new run on the same work order, copying independent upstream steps.
  """
  def retry_run(
        conn,
        %{
          "project_id" => project_id,
          "run_id" => run_id,
          "step_id" => step_id
        }
      ) do
    project = Projects.get_project!(project_id)
    current_user = conn.assigns.current_user

    with run <- Runs.get(run_id, include: [work_order: [:workflow]]),
         :ok <-
           Permissions.can(
             :project_users,
             :access_project,
             current_user,
             project
           ),
         :ok <- verify_run_belongs_to_project(run, project),
         :ok <-
           Permissions.can(
             :project_users,
             :run_workflow,
             current_user,
             project
           ),
         :ok <- WorkOrders.limit_run_creation(project_id),
         {:ok, new_run} <-
           WorkOrders.retry(run_id, step_id, created_by: current_user) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          run_id: new_run.id
        }
      })
    else
      {:error, _reason, %Lightning.Extensions.Message{} = message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message.text})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Failed to retry run",
          details: translate_changeset_errors(changeset)
        })

      {:error, :workflow_deleted} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Cannot retry run for deleted workflow"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def retry_run(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: step_id"})
  end

  defp verify_run_belongs_to_project(nil, _project) do
    {:error, :not_found}
  end

  defp verify_run_belongs_to_project(run, project) do
    if run.work_order.workflow.project_id == project.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp translate_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
