defmodule Lightning.FailureAlerter do
  @moduledoc false

  alias Lightning.Repo

  def alert(%{
        "workflow_id" => workflow_id,
        "workflow_name" => workflow_name,
        "run_id" => run_id,
        "project_id" => project_id,
        "work_order_id" => work_order_id,
        "recipient" => recipient
      }) do
    run = Repo.get!(Lightning.Invocation.Run, run_id)

    run_url = LightningWeb.RouteHelpers.show_run_path(project_id, run_id)

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
          run: run,
          workflow_name: workflow_name,
          workflow_id: workflow_id,
          run_url: run_url,
          recipient: recipient
        })
        |> case do
          {:ok, _metadata} ->
            :ok

          _ ->
            # decrement the counter when email is not delivered
            Hammer.check_rate_inc(
              bucket_key,
              time_scale,
              rate_limit,
              -1
            )

            {:cancel, "Failure email was not sent"}
        end

      {:deny, _} ->
        {:cancel, "Failure notification rate limit is reached"}
    end
  end
end
