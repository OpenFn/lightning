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
  alias Lightning.UsageTracking.Client
  alias Lightning.UsageTracking.Report
  alias Lightning.UsageTracking.ResubmissionWorker

  @impl Oban.Worker
  def perform(%{args: %{"batch_size" => batch_size}}) do
    host = Application.get_env(:lightning, :usage_tracking)[:host]

    if Client.reachable?(host) do
      query =
        from r in Report,
          where: r.submission_status == :failure,
          order_by: [asc: :inserted_at],
          limit: ^batch_size

      query
      |> Repo.all()
      |> Enum.each(fn report ->
        Oban.insert(Lightning.Oban, ResubmissionWorker.new(%{id: report.id}))
      end)
    end

    :ok
  end
end
