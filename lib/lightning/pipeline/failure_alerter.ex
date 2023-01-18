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

    bucket_key = "#{workflow_id}::#{recipient.id}"

    {:ok, {count, remaining, _, _, _}} =
      Hammer.inspect_bucket(bucket_key, time_scale, rate_limit)

    if remaining == 0 do
      {:cancel, "Failure notification rate limit is reached"}
    else
      Lightning.FailureEmail.deliver_failure_email(recipient.email, %{
        work_order_id: work_order_id,
        count: count + 1,
        run: run,
        workflow_name: workflow_name,
        workflow_id: workflow_id,
        run_url: run_url,
        recipient: recipient
      })
      |> case do
        {:ok, _metadata} ->
          # this increments the number of ops.
          Hammer.check_rate(
            bucket_key,
            time_scale,
            rate_limit
          )

          :ok

        _ ->
          {:cancel, "Failure email was not sent"}
      end
    end
  end
end
