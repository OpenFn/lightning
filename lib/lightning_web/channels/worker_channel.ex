defmodule LightningWeb.WorkerChannel do
  @moduledoc """
  Websocket channel to handle when workers join or claim something to run.
  """
  use LightningWeb, :channel

  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Runs
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workers

  alias LightningWeb.WorkerPresence

  require Logger

  @impl true
  def join("worker:queue", payload, %{assigns: %{claims: claims}} = socket)
      when not is_nil(claims) do
    # Extract capacity from payload, default to 1 if not provided
    capacity = Map.get(payload, "capacity", 1)

    # Track this worker's presence with its capacity
    worker_id = "worker-#{inspect(self())}"
    {:ok, _ref} = WorkerPresence.track_worker(self(), worker_id, capacity)

    # the work_listener_debounce_time assign is meant to be overidden in test mode.
    # a default value is set incase it's nil or not provided
    {:ok, pid} =
      LightningWeb.WorkListener.start_link(
        parent_pid: self(),
        debounce_time_ms: socket.assigns[:work_listener_debounce_time]
      )

    {:ok, assign(socket, work_listener_pid: pid)}
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
        Logger.debug("👉 Got {:ok, runs}, runs = #{inspect(runs)}")

        runs =
          runs
          |> Enum.map(fn run ->
            opts = run_options(run)
            Logger.debug("👉 Got run options, opts = #{inspect(opts)}")

            token = Workers.generate_run_token(run, opts)
            Logger.debug("👉 Got run token, token = #{inspect(token)}")

            %{
              "id" => run.id,
              "token" => token
            }
          end)

        Logger.debug(
          "👉 Sending back runs and socket, socket = #{inspect(socket)}"
        )

        {:reply, {:ok, %{runs: runs}}, socket}

      {:error, changeset} ->
        Logger.debug(
          "👉 Got {:error, changeset}, changeset = #{inspect(changeset)}"
        )

        errors = LightningWeb.ChangesetJSON.errors(changeset)

        Logger.debug(
          "👉 Calling ChangesetJSON.errors, errors = #{inspect(errors)}"
        )

        Logger.debug("👉 Responding with socket, socket = #{inspect(socket)}")

        {:reply, {:error, errors}, socket}
    end
  end

  @impl true
  def handle_info(:work_available, socket) do
    if Lightning.Config.broadcast_work_available?() do
      push(socket, "work-available", %{})
    end

    {:noreply, socket}
  end

  def handle_info(
        {:EXIT, pid, _reason},
        %{assigns: %{work_listener_pid: pid}} = socket
      ) do
    Logger.error("Work availability listener shutdown unexpectedly")
    {:noreply, assign(socket, work_listener_pid: nil)}
  end

  @impl true
  def terminate(reason, socket) do
    # Log unexpected termination reasons (crashes)
    case reason do
      :normal ->
        :ok

      :shutdown ->
        :ok

      {:shutdown, _} ->
        :ok

      error ->
        Logger.error("WorkerChannel terminated unexpectedly: #{inspect(error)}")
    end

    work_listener_pid = socket.assigns[:work_listener_pid]

    # copied this snippet from a Code BEAM Europe 2024 talk by Saša Jurić called Parenting
    # https://youtu.be/qTmpbzNDDqI?t=886
    if work_listener_pid do
      Process.exit(work_listener_pid, :shutdown)

      receive do
        {:EXIT, ^work_listener_pid, _reason} -> :ok
      after
        500 ->
          Process.exit(work_listener_pid, :kill)

          receive do
            {:EXIT, ^work_listener_pid, _reason} -> :ok
          end
      end
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
