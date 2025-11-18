defmodule LightningWeb.RunChannel do
  @moduledoc """
  Phoenix channel to interact with Runs.
  """
  use LightningWeb, :channel
  use LightningWeb, :verified_routes

  import LightningWeb.ChannelHelpers

  alias Lightning.Credentials
  alias Lightning.Credentials.Resolver
  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.Scrubber
  alias Lightning.Workers
  alias LightningWeb.RunWithOptions

  require Jason.Helpers
  require Logger

  @impl true
  def join(
        "run:" <> id,
        %{"token" => token},
        %{assigns: %{claims: worker_claims}} = socket
      )
      when not is_nil(worker_claims) do
    with {:ok, claims} <- Workers.verify_run_token(token, %{id: id}),
         run when is_map(run) <- Runs.get_for_worker(id) || {:error, :not_found},
         project_id when is_binary(project_id) <-
           Runs.get_project_id_for_run(run) do
      Logger.metadata(run_id: id, project_id: project_id)
      Sentry.Context.set_extra_context(%{run_id: id})

      {:ok,
       socket
       |> assign(%{
         claims: claims,
         id: id,
         run: run,
         project_id: project_id,
         scrubber: nil
       })}
    else
      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}

      _any ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join("run:" <> run_id, _params, socket)
      when is_map_key(socket.assigns, :current_user) do
    # Browser client join (from UserSocket)
    user = socket.assigns.current_user

    with run when is_map(run) <-
           Runs.get(run_id, include: [workflow: :project]) ||
             {:error, :not_found},
         project <- run.workflow.project,
         :ok <-
           Lightning.Policies.Permissions.can(
             Lightning.Policies.ProjectUsers,
             :access_project,
             user,
             project
           ) do
      # Subscribe to run events
      Runs.Events.subscribe(run)

      {:ok,
       socket
       |> assign(:run_id, run_id)
       |> assign(:project_id, project.id)}
    else
      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}

      {:error, :unauthorized} ->
        {:error, %{reason: "unauthorized"}}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join("run:" <> _id, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("fetch:plan", _payload, socket) do
    %{run: run} = socket.assigns

    reply_with(socket, {:ok, RunWithOptions.render(run)})
  end

  def handle_in("run:start", payload, socket) do
    case Runs.start_run(socket.assigns.run, payload) do
      {:ok, run} ->
        socket |> assign(run: run) |> reply_with({:ok, nil})

      {:error, changeset} ->
        reply_with(socket, {:error, changeset})
    end
  end

  def handle_in("run:complete", payload, socket) do
    case Runs.complete_run(socket.assigns.run, payload) do
      {:ok, run} ->
        # TODO: Turn FailureAlerter into an Oban worker and process async
        # instead of blocking the channel.
        run_with_preloads =
          run
          |> Repo.preload([:log_lines, work_order: [:workflow, :trigger]])

        run_with_preloads
        |> Lightning.FailureAlerter.alert_on_failure()

        # Broadcast webhook response if after_completion is enabled
        maybe_broadcast_webhook_response(run_with_preloads, payload)

        socket |> assign(run: run) |> reply_with({:ok, nil})

      {:error, changeset} ->
        reply_with(socket, {:error, changeset})
    end
  end

  def handle_in("fetch:credential", %{"id" => id}, socket) do
    %{run: run, project_id: project_id} = socket.assigns

    Logger.metadata(credential_id: id)

    case Resolver.resolve_credential(run, id) do
      {:ok, nil} ->
        reply_with(socket, {:ok, nil})

      {:ok, resolved_credential} ->
        handle_resolved_credential(socket, resolved_credential)

      {:error, :not_found} ->
        reply_with(socket, {:error, %{errors: %{id: ["Credential not found!"]}}})

      {:error, error_tuple} ->
        handle_credential_error(socket, error_tuple, id, project_id, run.id)
    end
  end

  def handle_in("fetch:credential", _payload, socket) do
    reply_with(
      socket,
      {:error, %{errors: %{id: ["This field can't be blank."]}}}
    )
  end

  @doc """
  For the time being, calls to `fetch:dataclip` will return dataclips that are
  preformatted for use as "initial state" in a run.

  This means that the body of http requests will be nested inside a "data" key.

  There is an open discussion on the community that may impact how we
  store HTTP requests in the database as dataclips and how we send the body
  of those HTTP requests to the worker to use as initial state.
  """
  def handle_in("fetch:dataclip", _payload, socket) do
    body = Runs.get_input(socket.assigns.run)

    if !socket.assigns.run.options.save_dataclips,
      do: Runs.wipe_dataclips(socket.assigns.run)

    reply_with(socket, {:ok, {:binary, body || "null"}})
  end

  def handle_in("step:start", payload, socket) do
    case Map.get(payload, "job_id", :missing_job_id) do
      job_id when is_binary(job_id) ->
        case Runs.start_step(socket.assigns.run, payload) do
          {:error, changeset} ->
            reply_with(socket, {:error, changeset})

          {:ok, step} ->
            reply_with(socket, {:ok, %{step_id: step.id}})
        end

      :missing_job_id ->
        reply_with(
          socket,
          {:error, %{errors: %{job_id: ["This field can't be blank."]}}}
        )

      nil ->
        reply_with(socket, {:error, %{errors: %{job_id: ["Job not found!"]}}})
    end
  end

  def handle_in("step:complete", payload, socket) do
    %{
      "run_id" => socket.assigns.run.id,
      "project_id" => socket.assigns.project_id
    }
    |> Enum.into(payload)
    |> Runs.complete_step(socket.assigns.run.options)
    |> case do
      {:error, changeset} ->
        reply_with(socket, {:error, changeset})

      {:ok, step} ->
        reply_with(socket, {:ok, %{step_id: step.id}})
    end
  end

  def handle_in("run:log", payload, socket) do
    %{"message" => message, "run_id" => run_id, "timestamp" => timestamp} =
      payload

    IO.puts(
      "RUN LOG A1 [#{run_id}] (#{DateTime.from_unix!(String.to_integer(timestamp), :microsecond)}) <#{message}> at #{DateTime.utc_now()}"
    )

    %{run: run, scrubber: scrubber} = socket.assigns

    case Runs.append_run_log(run, payload, scrubber) do
      {:error, changeset} ->
        reply_with(socket, {:error, changeset})

      {:ok, log_line} ->
        IO.puts(
          "RUN LOG A2 [#{run_id}] (#{DateTime.from_unix!(String.to_integer(timestamp), :microsecond)}) <#{message}> at #{DateTime.utc_now()}"
        )

        reply_with(socket, {:ok, %{log_line_id: log_line.id}})
    end
  end

  # Browser client handlers
  def handle_in("fetch:run", _payload, socket) do
    run_id = socket.assigns.run_id

    run =
      Runs.get(run_id,
        include: [
          :created_by,
          :starting_trigger,
          :work_order,
          steps: [:job, :input_dataclip, :output_dataclip]
        ]
      )

    reply_with(socket, {:ok, %{run: run}})
  end

  def handle_in("fetch:logs", _payload, socket) do
    run_id = socket.assigns.run_id
    run = Runs.get(run_id)

    # get_log_lines returns a stream that must be consumed in a transaction
    log_lines =
      Repo.transaction(fn ->
        Runs.get_log_lines(run)
        |> Enum.to_list()
      end)
      |> case do
        {:ok, lines} -> lines
        {:error, _} -> []
      end

    reply_with(socket, {:ok, %{logs: log_lines}})
  end

  # Forward PubSub events to browser clients
  @impl true
  def handle_info(%Runs.Events.RunUpdated{run: run}, socket) do
    push(socket, "run:updated", %{run: run})
    {:noreply, socket}
  end

  def handle_info(%Runs.Events.StepStarted{step: step}, socket) do
    step = Repo.preload(step, :job)
    push(socket, "step:started", %{step: step})
    {:noreply, socket}
  end

  def handle_info(%Runs.Events.StepCompleted{step: step}, socket) do
    step = Repo.preload(step, [:job, :input_dataclip, :output_dataclip])
    push(socket, "step:completed", %{step: step})
    {:noreply, socket}
  end

  def handle_info(%Runs.Events.LogAppended{log_line: log_line}, socket) do
    push(socket, "logs", %{logs: [log_line]})
    {:noreply, socket}
  end

  def handle_info(%Runs.Events.DataclipUpdated{dataclip: dataclip}, socket) do
    push(socket, "dataclip:updated", %{dataclip: dataclip})
    {:noreply, socket}
  end

  # Ignore other messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp maybe_broadcast_webhook_response(run, payload) do
    work_order = run.work_order
    trigger = work_order.trigger

    if trigger && trigger.type == :webhook &&
         trigger.webhook_reply == :after_completion do
      topic = "work_order:#{work_order.id}:webhook_response"

      # TODO - Later allow workflow authors to customize the status code
      # and body of the reply.
      status_code = determine_status_code(run.state)

      body = %{
        data: payload["final_state"],
        meta: %{
          work_order_id: work_order.id,
          run_id: run.id,
          state: run.state,
          error_type: run.error_type,
          inserted_at: run.inserted_at,
          started_at: run.started_at,
          claimed_at: run.claimed_at,
          finished_at: run.finished_at
        }
      }

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        topic,
        {:webhook_response, status_code, body}
      )
    end
  end

  # TODO - decide how we should respond... do we use HTTP codes for run states?
  defp determine_status_code(state) do
    case state do
      :success -> 201
      :failed -> 201
      :crashed -> 201
      :exception -> 201
      :killed -> 201
      :cancelled -> 201
      _other -> 201
    end
  end

  defp update_scrubber(nil, samples, basic_auth) do
    Scrubber.start_link(samples: samples, basic_auth: basic_auth)
  end

  defp update_scrubber(scrubber, samples, basic_auth) do
    :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
    {:ok, scrubber}
  end

  defp handle_resolved_credential(socket, resolved_credential) do
    samples = Credentials.sensitive_values_from_body(resolved_credential.body)
    basic_auth = Credentials.basic_auth_from_body(resolved_credential.body)

    {:ok, scrubber} =
      update_scrubber(socket.assigns.scrubber, samples, basic_auth)

    socket
    |> assign(scrubber: scrubber)
    |> reply_with({:ok, resolved_credential.body})
  end

  defp handle_credential_error(
         socket,
         {:environment_not_configured, _credential},
         _id,
         _project_id,
         _run_id
       ) do
    Logger.error("Project has no environment configured")

    error =
      LightningWeb.ErrorFormatter.format(:environment_not_configured, %{
        project: socket.assigns.project_id
      })

    {:reply, {:error, error}, socket}
  end

  defp handle_credential_error(
         socket,
         {:project_not_found, _credential},
         _id,
         _project_id,
         _run_id
       ) do
    Logger.error("Project not found for run")

    error = LightningWeb.ErrorFormatter.format(:project_not_found, %{})
    {:reply, {:error, error}, socket}
  end

  defp handle_credential_error(
         socket,
         {:environment_mismatch, credential},
         _id,
         _project_id,
         _run_id
       ) do
    project_env =
      Lightning.Projects.get_project!(socket.assigns.project_id).env || "unknown"

    Logger.error(
      "Credential environment does not match project environment",
      project_env: project_env
    )

    error =
      LightningWeb.ErrorFormatter.format(
        {:environment_mismatch, credential},
        %{project: socket.assigns.project_id, project_env: project_env}
      )

    {:reply, {:error, error}, socket}
  end

  defp handle_credential_error(
         socket,
         {:reauthorization_required, _credential} = reason,
         _id,
         _project_id,
         _run_id
       ) do
    Logger.error("OAuth refresh token has expired")

    error =
      LightningWeb.ErrorFormatter.format(reason, %{
        project: socket.assigns.project_id
      })

    {:reply, {:error, error}, socket}
  end

  defp handle_credential_error(
         socket,
         {:temporary_failure, _credential},
         _id,
         _project_id,
         _run_id
       ) do
    Logger.error("Could not reach the oauth provider")

    {:reply, {:error, "Could not reach the oauth provider. Try again later"},
     socket}
  end
end
