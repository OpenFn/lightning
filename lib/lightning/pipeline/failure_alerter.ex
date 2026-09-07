defmodule Lightning.FailureAlerter do
  @moduledoc false

  use LightningWeb, :verified_routes

  alias Lightning.Projects.MailRecipients
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Run

  require Logger

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
          "project" => project,
          "work_order_id" => run.work_order_id,
          "run_id" => run.id,
          "run_logs" => run.log_lines,
          "recipient" => user
        }
        |> Lightning.FailureAlerter.alert()
      end)
    end
  end

  # A recipient who may not be sent this project's contents is refused before
  # the rate limiter is consulted, so an allowance is only ever spent on mail
  # that is actually sent. Charging a slot for a refused recipient would make
  # the alert budget depend on who is refused rather than on how often the
  # workflow failed.
  def alert(%{"project" => project, "recipient" => recipient} = attrs) do
    if MailRecipients.may_receive?(project, recipient) do
      deliver_alert(attrs)
    else
      Logger.info(
        "Withheld failure alert from user #{recipient.id} in project " <>
          "#{project.id}: they may not be sent this project's contents"
      )

      nil
    end
  end

  defp deliver_alert(%{
         "workflow_id" => workflow_id,
         "workflow_name" => workflow_name,
         "project" => project,
         "work_order_id" => work_order_id,
         "run_id" => run_id,
         "run_logs" => run_logs,
         "recipient" => recipient
       }) do
    [time_scale: time_scale, rate_limit: rate_limit] =
      Application.fetch_env!(:lightning, __MODULE__)

    run_url =
      url(
        LightningWeb.Endpoint,
        ~p"/projects/#{project.id}/runs/#{run_id}"
      )

    work_order_url =
      url(
        LightningWeb.Endpoint,
        ~p"/projects/#{project.id}/history?filters[workorder_id]=#{work_order_id}"
      )

    # rate limiting per workflow AND user
    bucket_key = "#{workflow_id}::#{recipient.id}"

    Hammer.check_rate(
      bucket_key,
      time_scale,
      rate_limit
    )
    |> case do
      {:allow, count} ->
        ordered_logs = Enum.sort_by(run_logs, & &1.timestamp, DateTime)

        Lightning.FailureEmail.deliver_failure_email(recipient.email, %{
          work_order_id: work_order_id,
          work_order_url: work_order_url,
          count: count,
          time_scale: time_scale,
          rate_limit: rate_limit,
          run_id: run_id,
          run_url: run_url,
          run_logs: ordered_logs,
          project_name: project.name,
          workflow_name: workflow_name,
          workflow_id: workflow_id,
          recipient: recipient
        })
        |> case do
          {:ok, _metadata} ->
            nil

          # :ok

          _ ->
            # decrement the counter when email is not delivered
            Hammer.check_rate_inc(
              bucket_key,
              time_scale,
              rate_limit,
              -1
            )

            nil
            # {:cancel, "Failure email was not sent"} or Logger
        end

      {:deny, _} ->
        nil
        # {:cancel, "Failure notification rate limit is reached"} or Logger
    end
  end
end
