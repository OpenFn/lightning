defmodule LightningWeb.WorkerChannel do
  @moduledoc """
  Websocket channel to handle when workers join or claim something to run.
  """
  use LightningWeb, :channel

  alias Lightning.Runs
  alias Lightning.Workers

  @impl true
  def join("worker:queue", _payload, %{assigns: %{token: token}} = socket) do
    case Workers.verify_worker_token(token) do
      {:ok, claims} ->
        {:ok, assign(socket, :claims, claims)}

      {:error, _} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join("worker:queue", _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("claim", %{"demand" => demand}, socket) do
    case Runs.claim(demand) do
      {:ok, runs} ->
        runs =
          runs
          |> Enum.map(fn run ->
            token = Lightning.Workers.generate_run_token(run)

            %{
              "id" => run.id,
              "token" => token
            }
          end)

        {:reply, {:ok, %{runs: runs}}, socket}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}
    end
  end
end
