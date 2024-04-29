defmodule Lightning.KafkaTriggers.PipelineSupervisor do
  use Supervisor

  alias Lightning.KafkaTriggers
  alias Lightning.Repo
  alias Lightning.Workflows.Trigger
  # alias Lightning.KafkaTriggers.Pipeline

  def start_link(opts) do
    test_pid = Keyword.get(opts, :test_pid)

    {:ok, pid} = Supervisor.start_link(__MODULE__, [], opts)

    Ecto.Adapters.SQL.Sandbox.allow(Repo, test_pid, pid)

    {:ok, pid}
  end

  @impl true
  def init(_opts) do
      Trigger |> Repo.all() |> IO.inspect(label: :code)
    children =
      KafkaTriggers.find_enabled_triggers()
      |> IO.inspect()
      |> Enum.map(& %{id: &1.id})
      |> IO.inspect()
      
    Supervisor.init(children, strategy: :one_for_one)
  end
end
