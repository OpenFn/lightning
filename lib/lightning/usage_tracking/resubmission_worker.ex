defmodule Lightning.UsageTracking.ResubmissionWorker do
  @moduledoc """
  Worker to resubmit report that has failed submission.

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.UsageTracking
  alias Lightning.UsageTracking.Report

  @impl Oban.Worker
  def perform(%{args: %{"id" => id}}) do
    env = Application.get_env(:lightning, :usage_tracking)

    resubmit_report(id, env[:host], env[:enabled])

    :ok
  end

  defp resubmit_report(id, host, true = _enabled) do
    Repo.transaction(fn ->
      query =
        from r in Report,
          where: r.id == ^id,
          where: r.submission_status == :failure,
          lock: "FOR UPDATE SKIP LOCKED"

      if report = Repo.one(query) do
        UsageTracking.submit_report(report, host)
      end
    end)
  end

  defp resubmit_report(_id, _host, false = _enabled), do: nil
end
