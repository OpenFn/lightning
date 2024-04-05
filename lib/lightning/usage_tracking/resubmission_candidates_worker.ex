defmodule Lightning.UsageTracking.ResubmissionCandidatesWorker do
  @moduledoc """
  Worker to find reports that have failed submissions and enqueue jobs to
  reprocess them.

  """
  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ResubmissionWorker

  @impl Oban.Worker
  def perform(%{args: %{"batch_size" => _batch_size}}) do
    query = from r in Report, where: r.submission_status == :failure

    query
    |> Repo.all()
    |> Enum.each(fn report ->
      Oban.insert(Lightning.Oban, ResubmissionWorker.new(%{id: report.id}))
    end)

    :ok
  end
end
