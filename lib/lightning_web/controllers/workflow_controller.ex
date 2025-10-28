defmodule LightningWeb.WorkflowController do
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Workflows
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
end
