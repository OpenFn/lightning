defmodule Lightning.FailureAlerter do
  @moduledoc false

  alias Lightning.Repo

  def alert_on_failure(run) when run.exit_reason == "success", do: nil

  def alert_on_failure(run) do
    attempt = Lightning.AttemptService.get_last_attempt_for(run)

    attempt
    |> case do
      nil ->
        nil

      attempt ->
        work_order = attempt.work_order
        workflow = attempt.work_order.workflow

        Lightning.Accounts.get_users_to_alert_for_project(%{
          id: workflow.project_id
        })
        |> Enum.each(fn user ->
          %{
            "workflow_id" => workflow.id,
            "workflow_name" => workflow.name,
            "run_id" => run.id,
            "project_id" => workflow.project_id,
            "work_order_id" => work_order.id,
            "recipient" => user
          }
          |> Lightning.FailureAlerter.alert()
        end)
    end
  end

  def alert(%{
        "workflow_id" => workflow_id,
        "workflow_name" => workflow_name,
        "run_id" => run_id,
        "project_id" => project_id,
        "work_order_id" => work_order_id,
        "recipient" => recipient
      }) do
    run = Repo.get!(Lightning.Invocation.Run, run_id)

    run_url = LightningWeb.RouteHelpers.show_run_url(project_id, run_id)

    [time_scale: time_scale, rate_limit: rate_limit] =
      Application.fetch_env!(:lightning, __MODULE__)

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
          run: run |> Repo.preload(:log_lines),
          workflow_name: workflow_name,
          workflow_id: workflow_id,
          run_url: run_url,
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
