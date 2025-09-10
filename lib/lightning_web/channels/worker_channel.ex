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

  The mechanism works across a cluster of Lightning nodes using Phoenix.PubSub
  for cross-node communication. When a run channel is joined on any node, it
  broadcasts a message that the worker channel (potentially on a different node)
  can receive and use to cancel the timeout.

  The timeout can be configured via the `:claim_timeout_seconds` application
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

    {:ok, assign(socket, work_listener_pid: pid, worker_id: worker_id)}
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
          # Start a timeout to ensure the client joins the run channels
          timeout_ms = claim_timeout_ms()

          timeout_ref =
            :timer.send_after(
              timeout_ms,
              self(),
              {:claim_timeout, original_runs}
            )

          # Store the timeout reference and original runs in socket assigns
          socket =
            assign(socket,
              claim_timeout_ref: timeout_ref,
              pending_runs: original_runs
            )

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

  def handle_info({:claim_timeout, runs}, socket) do
    # Timeout occurred - client didn't join run channels in time
    Logger.warning(
      "Claim timeout reached, rolling back transaction for runs: #{Enum.map_join(runs, ", ", & &1.id)}"
    )

    {:ok, count} = Runs.rollback_claimed_runs(runs)
    Logger.info("Successfully rolled back #{count} runs")

    # Clear the timeout reference and pending runs from socket assigns
    socket = assign(socket, claim_timeout_ref: nil, pending_runs: nil)

    {:noreply, socket}
  end

  def handle_info({:run_channel_joined, run_id}, socket) do
    # Client successfully joined a run channel, cancel timeout if this was the last pending run
    case socket.assigns[:pending_runs] do
      nil ->
        # No pending runs, nothing to do
        {:noreply, socket}

      pending_runs ->
        # Remove the joined run from pending runs
        remaining_runs = Enum.reject(pending_runs, &(&1.id == run_id))

        if Enum.empty?(remaining_runs) do
          # All runs have been joined, cancel the timeout
          case socket.assigns[:claim_timeout_ref] do
            nil ->
              {:noreply, socket}

            timeout_ref ->
              :timer.cancel(timeout_ref)
              socket = assign(socket, claim_timeout_ref: nil, pending_runs: nil)
              {:noreply, socket}
          end
        else
          # Still have pending runs, update the list
          socket = assign(socket, pending_runs: remaining_runs)
          {:noreply, socket}
        end
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

    # Clean up any pending claim timeout
    case socket.assigns[:claim_timeout_ref] do
      nil ->
        :ok

      timeout_ref ->
        :timer.cancel(timeout_ref)

        # Roll back any pending runs since the worker is disconnecting
        case socket.assigns[:pending_runs] do
          nil ->
            :ok

          pending_runs ->
            Logger.warning(
              "Worker channel terminating with pending runs, rolling back: #{Enum.map_join(pending_runs, ", ", & &1.id)}"
            )

            Runs.rollback_claimed_runs(pending_runs)
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

  defp claim_timeout_ms do
    # Default to 30 seconds if not configured
    Application.get_env(:lightning, :claim_timeout_seconds, 30) * 1000
  end
end
