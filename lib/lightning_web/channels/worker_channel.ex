defmodule LightningWeb.WorkerChannel do
  @moduledoc """
  Websocket channel to handle when workers join or claim something to run.
  """
  use LightningWeb, :channel

  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Runs
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workers

  @impl true
  def join("worker:queue", _payload, %{assigns: %{claims: claims}} = socket)
      when not is_nil(claims) do
    {:ok, socket}
  end

  def join("worker:queue", _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in(
        "claim",
        %{"demand" => demand, "worker_name" => worker_name},
        socket
      ) do
    case Runs.claim(demand, sanitise_worker_name(worker_name)) do
      {:ok, runs} ->
        runs =
          runs
          |> Enum.map(fn run ->
            opts = run_options(run)

            token = Workers.generate_run_token(run, opts)

            %{
              "id" => run.id,
              "token" => token
            }
          end)

        {:reply, {:ok, %{runs: runs}}, socket}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.errors(changeset)}, socket}
    end
  end

  defp sanitise_worker_name(""), do: nil

  defp sanitise_worker_name(worker_name), do: worker_name

  defp run_options(run) do
    Ecto.assoc(run, :workflow)
    |> Lightning.Repo.one()
    |> then(fn %{project_id: project_id} ->
      UsageLimiter.get_run_options(%Context{project_id: project_id})
    end)
    |> Enum.into(%{})
    |> Runs.RunOptions.new()
    |> Ecto.Changeset.apply_changes()
  end
end
