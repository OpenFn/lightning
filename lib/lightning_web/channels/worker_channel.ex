defmodule LightningWeb.WorkerChannel do
  @moduledoc """
  Websocket channel to handle when workers join or claim something to run.

  ## Claim Timeout Mechanism

  When a worker claims runs, the system starts a timeout to ensure the client
  joins the corresponding run channels. If the client doesn't join the run
  channels within the configured timeout period (default 30 seconds), the
  claimed runs are automatically rolled back to :available state so they can
  be claimed by another worker.

  This prevents runs from being stuck in :claimed state if the client
  disconnects or fails to join the run channels after receiving the claim reply.

  The mechanism supports multiple concurrent claims by tracking each individual run
  with its own timeout. This prevents newer claims from overwriting timeout coverage
  of earlier claims.

  The mechanism works across a cluster of Lightning nodes using Phoenix.PubSub
  for cross-node communication. When a run channel is joined on any node, it
  broadcasts a message that the worker channel (potentially on a different node)
  can receive and use to cancel the timeout.

  The timeout can be configured via the `:run_channel_join_timeout_seconds` application
  environment variable.
  """
  use LightningWeb, :channel

  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Runs
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workers

  require Logger

  @impl true
  def join("worker:queue", _payload, %{assigns: %{claims: claims}} = socket)
      when not is_nil(claims) do
    # the work_listener_debounce_time assign is meant to be overidden in test mode.
    # a default value is set incase it's nil or not provided
    {:ok, pid} =
      LightningWeb.WorkListener.start_link(
        parent_pid: self(),
        debounce_time_ms: socket.assigns[:work_listener_debounce_time]
      )

    # Subscribe to run channel join notifications for this worker
    # This allows cross-node communication in clustered environments
    worker_id = socket.assigns[:worker_id] || socket.id
    Lightning.subscribe("worker_channel:#{worker_id}")

    {:ok,
     assign(socket,
       work_listener_pid: pid,
       worker_id: worker_id,
       pending_run_timeouts: %{}
     )}
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
      {:ok, original_runs} ->
        # Prepare the response data
        response_runs =
          original_runs
          |> Enum.map(fn run ->
            opts = run_options(run)

            token = Workers.generate_run_token(run, opts)

            %{
              "id" => run.id,
              "token" => token
            }
          end)

        # Check if the socket is still alive
        if Process.alive?(socket.transport_pid) do
          # Only start timeout if we actually have runs to track
          socket =
            if Enum.count(original_runs) > 0 do
              # Start a timeout for each individual run
              timeout_ms =
                Lightning.Config.run_channel_join_timeout_seconds() * 1000

              pending_run_timeouts = socket.assigns[:pending_run_timeouts] || %{}

              # Create a timeout for each run
              updated_timeouts =
                Enum.reduce(original_runs, pending_run_timeouts, fn run, acc ->
                  timeout_ref =
                    :timer.send_after(
                      timeout_ms,
                      self(),
                      {:run_timeout, run.id, run}
                    )

                  Map.put(acc, run.id, timeout_ref)
                end)

              assign(socket, pending_run_timeouts: updated_timeouts)
            else
              socket
            end

          {:reply, {:ok, %{runs: response_runs}}, socket}
        else
          # Socket is no longer alive, roll back the transaction by setting runs back to :available
          Logger.warning(
            "Worker socket disconnected before claim reply, rolling back transaction for runs: #{Enum.map_join(original_runs, ", ", & &1.id)}"
          )

          Runs.rollback_claimed_runs(original_runs)

          {:noreply, socket}
        end

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.errors(changeset)}, socket}
    end
  end

  @impl true
  def handle_info(:work_available, socket) do
    push(socket, "work-available", %{})
    {:noreply, socket}
  end

  def handle_info(
        {:EXIT, pid, _reason},
        %{assigns: %{work_listener_pid: pid}} = socket
      ) do
    Logger.error("Work availability listener shutdown unexpectedly")
    {:noreply, assign(socket, work_listener_pid: nil)}
  end

  def handle_info({:run_timeout, run_id, run}, socket) do
    # Timeout occurred - client didn't join run channel in time
    Logger.warning(
      "Run timeout reached for run #{run_id}, rolling back transaction"
    )

    {:ok, count} = Runs.rollback_claimed_runs([run])
    Logger.info("Successfully rolled back #{count} run (#{run_id})")

    # Remove this run's timeout from pending_run_timeouts
    pending_run_timeouts = socket.assigns[:pending_run_timeouts] || %{}
    updated_timeouts = Map.delete(pending_run_timeouts, run_id)
    socket = assign(socket, pending_run_timeouts: updated_timeouts)

    {:noreply, socket}
  end

  def handle_info({:run_channel_joined, run_id}, socket) do
    # Client successfully joined a run channel, cancel the timeout for this specific run
    pending_run_timeouts = socket.assigns[:pending_run_timeouts] || %{}

    case Map.get(pending_run_timeouts, run_id) do
      nil ->
        # No timeout for this run, nothing to do
        {:noreply, socket}

      timeout_ref ->
        # Cancel the timeout and remove it from tracking
        :timer.cancel(timeout_ref)
        updated_timeouts = Map.delete(pending_run_timeouts, run_id)
        socket = assign(socket, pending_run_timeouts: updated_timeouts)
        {:noreply, socket}
    end
  end

  def handle_info({:run_channel_joined, run_id, worker_id}, socket) do
    # Handle PubSub message for run channel join notification
    # Only process if this message is for this worker
    case socket.assigns[:worker_id] do
      ^worker_id ->
        handle_info({:run_channel_joined, run_id}, socket)

      _ ->
        # Message not for this worker, ignore
        {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
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

    # Unsubscribe from PubSub
    case socket.assigns[:worker_id] do
      nil ->
        :ok

      worker_id ->
        Lightning.unsubscribe("worker_channel:#{worker_id}")
    end

    # Clean up any pending run timeouts
    pending_run_timeouts = socket.assigns[:pending_run_timeouts] || %{}

    unless Enum.empty?(pending_run_timeouts) do
      Enum.each(pending_run_timeouts, fn {run_id, timeout_ref} ->
        # Cancel the timeout
        :timer.cancel(timeout_ref)

        Logger.warning(
          "Worker channel terminating with pending run timeout for run #{run_id}"
        )
      end)

      run_ids = Map.keys(pending_run_timeouts)

      if not Enum.empty?(run_ids) do
        Logger.warning(
          "Worker channel terminating with pending run timeouts for runs: #{Enum.join(run_ids, ", ")}"
        )
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
