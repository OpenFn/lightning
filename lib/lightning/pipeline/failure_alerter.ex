defmodule Lightning.FailureAlerter do
  @moduledoc false

  alias Lightning.Attempt

  def alert_on_failure(nil), do: nil

  def alert_on_failure(%Attempt{state: state}) when state == :success,
    do: nil

  def alert_on_failure(%Attempt{} = attempt) do
    workflow = attempt.work_order.workflow

    Lightning.Accounts.get_users_to_alert_for_project(%{
      id: workflow.project_id
    })
    |> Enum.each(fn user ->
      %{
        "workflow_id" => workflow.id,
        "workflow_name" => workflow.name,
        "work_order_id" => attempt.work_order_id,
        "attempt_id" => attempt.id,
        "project_id" => workflow.project_id,
        "attempt_logs" => attempt.log_lines,
        "recipient" => user
      }
      |> Lightning.FailureAlerter.alert()
    end)
  end

  def alert(%{
        "workflow_id" => workflow_id,
        "workflow_name" => workflow_name,
        "work_order_id" => work_order_id,
        "attempt_id" => attempt_id,
        "project_id" => project_id,
        "attempt_logs" => attempt_logs,
        "recipient" => recipient
      }) do
    [time_scale: time_scale, rate_limit: rate_limit] =
      Application.fetch_env!(:lightning, __MODULE__)

    attempt_url =
      LightningWeb.RouteHelpers.show_attempt_url(project_id, attempt_id)

    # rate limiting per workflow AND user
    bucket_key = "#{workflow_id}::#{recipient.id}"

    Hammer.check_rate(
      bucket_key,
      time_scale,
      rate_limit
    )
    |> case do
      {:allow, count} ->
        Lightning.FailureEmail.deliver_failure_email(recipient.email, %{
          work_order_id: work_order_id,
          count: count,
          time_scale: time_scale,
          rate_limit: rate_limit,
          attempt_id: attempt_id,
          attempt_url: attempt_url,
          attempt_logs: attempt_logs,
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
