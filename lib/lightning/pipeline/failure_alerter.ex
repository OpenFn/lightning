defmodule Lightning.FailureAlerter do
  @moduledoc false

  use LightningWeb, :verified_routes

  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Run

  def alert_on_failure(nil), do: nil

  def alert_on_failure(%Run{state: state}) when state == :success,
    do: nil

  def alert_on_failure(%Run{} = run) do
    workflow = run.work_order.workflow

    if :ok == ProjectLimiter.limit_failure_alert(workflow.project_id) do
      project = Lightning.Projects.get_project!(workflow.project_id)

      Lightning.Accounts.get_users_to_alert_for_project(%{
        id: workflow.project_id
      })
      |> Enum.each(fn user ->
        %{
          "workflow_id" => workflow.id,
          "workflow_name" => workflow.name,
          "project_name" => project.name,
          "work_order_id" => run.work_order_id,
          "run_id" => run.id,
          "project_id" => workflow.project_id,
          "run_logs" => run.log_lines,
          "recipient" => user
        }
        |> Lightning.FailureAlerter.alert()
      end)
    end
  end

  def alert(%{
        "workflow_id" => workflow_id,
        "workflow_name" => workflow_name,
        "project_name" => project_name,
        "work_order_id" => work_order_id,
        "run_id" => run_id,
        "project_id" => project_id,
        "run_logs" => run_logs,
        "recipient" => recipient
      }) do
    run_url = ~p"/projects/#{project_id}/runs/#{run_id}"

    work_order_url =
      ~p"/projects/#{project_id}/history?filters[workorder_id]=#{work_order_id}"

    Lightning.RateLimiters.hit({:failure_email, workflow_id, recipient.id})
    |> case do
      {:allow, %{count: count, time_scale: time_scale, rate_limit: rate_limit}} ->
        Lightning.FailureEmail.deliver_failure_email(recipient.email, %{
          work_order_id: work_order_id,
          work_order_url: work_order_url,
          count: count,
          time_scale: time_scale,
          rate_limit: rate_limit,
          run_id: run_id,
          run_url: run_url,
          run_logs: run_logs,
          project_name: project_name,
          workflow_name: workflow_name,
          workflow_id: workflow_id,
          recipient: recipient
        })

      {:deny, _} ->
        nil
    end
  end
end
