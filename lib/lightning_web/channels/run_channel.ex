defmodule LightningWeb.RunChannel do
  @moduledoc """
  Phoenix channel to interact with Runs.
  """
  use LightningWeb, :channel
  use LightningWeb, :verified_routes

  import LightningWeb.ChannelHelpers

  alias Lightning.Credentials.Resolver
  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.Workers
  alias LightningWeb.RunWithOptions

  require Jason.Helpers
  require Logger

  defmodule WebhookResponse do
    @moduledoc false
    defstruct status: nil, body: nil, step_id: nil, sent_at: nil
  end

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
         scrubber: nil,
         webhook_response: nil
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
    payload = Map.put(payload, "project_id", socket.assigns.project_id)

    case Runs.complete_run(socket.assigns.run, payload) do
      {:ok, run} ->
        # TODO: Turn FailureAlerter into an Oban worker and process async
        # instead of blocking the channel.
        run_with_preloads =
          run
          |> Repo.preload([:log_lines, work_order: [:workflow]])

        run_with_preloads
        |> Lightning.FailureAlerter.alert_on_failure()

        socket
        |> assign(run: run)
        |> maybe_send_after_completion_response(payload["final_state"])
        |> reply_with({:ok, nil})

      {:error, changeset} ->
        reply_with(socket, {:error, changeset})
    end
  end

  def handle_in("fetch:credential", %{"id" => id}, socket) do
    %{run: run, project_id: project_id} = socket.assigns

    Logger.metadata(credential_id: id)

    credential =
      case Resolver.resolve_credential(run, id) do
        {:ok, %{credential: credential}} -> credential
        {:error, {_reason, credential}} -> credential
        _ -> nil
      end

    error =
      LightningWeb.ErrorFormatter.format(
        {:reauthorization_required, credential},
        %{project: project_id}
      )

    reply_with(socket, {:error, error})
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
        socket
        |> put_webhook_response(payload)
        |> reply_with({:ok, %{step_id: step.id}})
    end
  end

  def handle_in("run:log", payload, socket) do
    %{run: run, scrubber: scrubber} = socket.assigns

    case Runs.append_run_log(run, payload, scrubber) do
      {:error, changeset} ->
        reply_with(socket, {:error, changeset})

      {:ok, log_line} ->
        reply_with(socket, {:ok, %{log_line_id: log_line.id}})
    end
  end

  def handle_in("run:batch_logs", %{"logs" => payload}, socket) do
    %{run: run, scrubber: scrubber} = socket.assigns

    case Runs.append_run_logs_batch(run, payload, scrubber) do
      {:error, changeset} ->
        reply_with(socket, {:error, changeset})

      {:ok, _} ->
        reply_with(socket, :ok)
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
    run = Repo.preload(run, :steps)
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

  defp put_webhook_response(socket, payload) do
    if already_sent?(socket.assigns.webhook_response) do
      socket
    else
      case Map.get(payload, "webhook_response") do
        %{} = wr ->
          assign(socket, :webhook_response, %WebhookResponse{
            status: Map.get(wr, "status"),
            body: Map.get(wr, "body"),
            step_id: Map.get(payload, "step_id")
          })

        _ ->
          socket
      end
    end
  end

  defp already_sent?(%WebhookResponse{sent_at: %DateTime{}}), do: true
  defp already_sent?(_), do: false

  defp maybe_send_after_completion_response(socket, final_state) do
    run = Repo.preload(socket.assigns.run, :starting_trigger)
    trigger = run.starting_trigger

    if trigger && trigger.webhook_reply == :after_completion do
      webhook_response =
        build_webhook_response(
          run,
          final_state,
          trigger.webhook_response_config,
          socket.assigns.webhook_response
        )

      socket
      |> assign(:webhook_response, webhook_response)
      |> maybe_broadcast_webhook_response()
    else
      socket
    end
  end

  defp maybe_broadcast_webhook_response(socket) do
    %{run: run, webhook_response: %WebhookResponse{} = webhook_response} =
      socket.assigns

    if already_sent?(webhook_response) do
      socket
    else
      meta = %{
        work_order_id: run.work_order_id,
        run_id: run.id,
        state: run.state,
        error_type: run.error_type,
        inserted_at: run.inserted_at,
        started_at: run.started_at,
        claimed_at: run.claimed_at,
        finished_at: run.finished_at
      }

      Phoenix.PubSub.broadcast(
        Lightning.PubSub,
        "work_order:#{run.work_order_id}:webhook_response",
        {:webhook_response, webhook_response.status,
         %{data: webhook_response.body, meta: meta}}
      )

      assign(socket, :webhook_response, %{
        webhook_response
        | sent_at: DateTime.utc_now()
      })
    end
  end

  defp build_webhook_response(run, final_state, config, nil) do
    {status, body} = build_default_response(run, final_state, config)
    %WebhookResponse{status: status, body: body}
  end

  defp build_webhook_response(
         run,
         final_state,
         config,
         %WebhookResponse{} = webhook_response
       ) do
    with {:ok, custom_status} <- parse_webhook_status(webhook_response.status),
         {:ok, custom_body} <- parse_webhook_body(webhook_response.body) do
      status = custom_status || default_response_status(run.state, config)
      body = custom_body || default_response_body(run.state, final_state, config)
      %{webhook_response | status: status, body: body}
    else
      {:error, reason} ->
        {status, body} = malformed_response(reason, run, config)
        %{webhook_response | status: status, body: body}
    end
  end

  defp parse_webhook_status(nil), do: {:ok, nil}
  defp parse_webhook_status(status) when is_integer(status), do: {:ok, status}

  defp parse_webhook_status(status) when is_float(status),
    do: {:ok, trunc(status)}

  defp parse_webhook_status(status),
    do: {:error, "status needs to be an integer, got: #{inspect(status)}"}

  defp parse_webhook_body(nil), do: {:ok, nil}
  defp parse_webhook_body(body) when is_map(body), do: {:ok, body}

  defp parse_webhook_body(body),
    do: {:error, "body needs to be a JSON object, got: #{inspect(body)}"}

  defp build_default_response(run, final_state, config) do
    {default_response_status(run.state, config),
     default_response_body(run.state, final_state, config)}
  end

  defp default_response_status(:success, %{success_code: code})
       when is_integer(code),
       do: code

  defp default_response_status(:success, _config), do: 201

  defp default_response_status(_run_status, %{error_code: code})
       when is_integer(code),
       do: code

  defp default_response_status(_run_status, _config), do: 201

  defp default_response_body(:success, final_state, _config),
    do: final_state

  defp default_response_body(run_status, _final_state, _config) do
    %{
      message:
        "Run completed with status: #{run_status}. As a security policy, OpenFn does not send state data when the run errors out to avoid leaking sensitive information"
    }
  end

  defp malformed_response(reason, run, config) do
    {default_response_status(run.state, config),
     %{message: "Run completed, but webhook_response was malformed: #{reason}"}}
  end
end
