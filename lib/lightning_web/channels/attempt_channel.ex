defmodule LightningWeb.AttemptChannel do
  @moduledoc """
  Phoenix channel to interact with Attempts.
  """
  use LightningWeb, :channel

  alias Lightning.Attempts
  alias Lightning.Credentials
  alias Lightning.Repo
  alias Lightning.Scrubber
  alias Lightning.Workers
  alias LightningWeb.AttemptJson

  require Jason.Helpers
  require Logger

  @impl true
  def join(
        "attempt:" <> id,
        %{"token" => token},
        %{assigns: %{token: worker_token}} = socket
      ) do
    with {:ok, _} <- Workers.verify_worker_token(worker_token),
         {:ok, claims} <- Workers.verify_attempt_token(token, %{id: id}),
         attempt when is_map(attempt) <- get_attempt(id) || {:error, :not_found},
         project_id when is_binary(project_id) <-
           Attempts.get_project_id_for_attempt(attempt) do
      {:ok,
       socket
       |> assign(%{
         claims: claims,
         id: id,
         attempt: attempt,
         project_id: project_id,
         scrubber: nil
       })}
    else
      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join("attempt:" <> _, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("fetch:attempt", _, socket) do
    {:reply, {:ok, AttemptJson.render(socket.assigns.attempt)}, socket}
  end

  def handle_in("attempt:start", _, socket) do
    socket.assigns.attempt
    |> Attempts.start_attempt()
    |> case do
      {:ok, attempt} ->
        {:reply, {:ok, nil}, socket |> assign(attempt: attempt)}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}
    end
  end

  def handle_in("attempt:complete", payload, socket) do
    params =
      payload |> replace_reason_with_exit_reason()

    socket.assigns.attempt
    |> Attempts.complete_attempt(params)
    |> case do
      {:ok, attempt} ->
        # TODO: Turn FailureAlerter into an Oban worker and process async
        # instead of blocking the channel.
        attempt
        |> Repo.preload([:log_lines, work_order: [:workflow]])
        |> Lightning.FailureAlerter.alert_on_failure()

        {:reply, {:ok, nil}, socket |> assign(attempt: attempt)}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}
    end
  end

  def handle_in("fetch:credential", %{"id" => id}, socket) do
    %{attempt: attempt, scrubber: scrubber} = socket.assigns

    with credential <- Attempts.get_credential(attempt, id) || :not_found,
         {:ok, credential} <- Credentials.maybe_refresh_token(credential),
         samples <- Credentials.sensitive_values_for(credential),
         basic_auth <- Credentials.basic_auth_for(credential),
         {:ok, scrubber} <- update_scrubber(scrubber, samples, basic_auth) do
      socket = assign(socket, scrubber: scrubber)

      {:reply, {:ok, credential.body}, socket}
    else
      :not_found ->
        {:reply, {:error, %{errors: %{id: ["Credential not found!"]}}}, socket}

      {:error, error} ->
        Logger.error(fn ->
          """
          Something went wrong when fetching or refreshing a credential.

          #{inspect(error)}
          """
        end)

        {:reply,
         {:error,
          %{errors: "Something went wrong when retrieving the credential"}},
         socket}
    end
  end

  def handle_in("fetch:credential", _, socket) do
    {:reply, {:error, %{errors: %{id: ["This field can't be blank."]}}}, socket}
  end

  @doc """
  For the time being, calls to `fetch:dataclip` will return dataclips that are
  preformatted for use as "initial state" in an attempt.

  This means that the body of http requests will be nested inside a "data" key.

  There is an open discussion on the community that may impact how we
  store HTTP requests in the database as dataclips and how we send the body
  of those HTTP requests to the worker to use as initial state.
  """
  def handle_in("fetch:dataclip", _, socket) do
    {type, raw_body} = Attempts.get_dataclip_for_worker(socket.assigns.attempt)

    body =
      if type == :http_request,
        do: "{\"data\": " <> raw_body <> "}",
        else: raw_body

    {:reply, {:ok, {:binary, body}}, socket}
  end

  # TODO - remove after worker update.
  def handle_in("run:start", payload, socket),
    do: handle_in("step:start", payload, socket)

  def handle_in("step:start", payload, socket) do
    Map.get(payload, "job_id", :missing_job_id)
    |> case do
      job_id when is_binary(job_id) ->
        %{"attempt_id" => socket.assigns.attempt.id}
        |> Enum.into(payload)
        |> Attempts.start_step()
        |> case do
          {:error, changeset} ->
            {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)},
             socket}

          {:ok, step} ->
            {:reply, {:ok, %{step_id: step.id}}, socket}
        end

      :missing_job_id ->
        {:reply, {:error, %{errors: %{job_id: ["This field can't be blank."]}}},
         socket}

      nil ->
        {:reply, {:error, %{errors: %{job_id: ["Job not found!"]}}}, socket}
    end
  end

  # TODO - remove after worker update.
  def handle_in("run:complete", payload, socket),
    do: handle_in("step:complete", payload, socket)

  def handle_in("step:complete", payload, socket) do
    %{
      "attempt_id" => socket.assigns.attempt.id,
      "project_id" => socket.assigns.project_id
    }
    |> Enum.into(payload)
    |> Attempts.complete_step()
    |> case do
      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}

      {:ok, step} ->
        {:reply, {:ok, %{step_id: step.id}}, socket}
    end
  end

  def handle_in("attempt:log", payload, socket) do
    %{attempt: attempt, scrubber: scrubber} = socket.assigns

    Attempts.append_attempt_log(attempt, payload, scrubber)
    |> case do
      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}

      {:ok, log_line} ->
        {:reply, {:ok, %{log_line_id: log_line.id}}, socket}
    end
  end

  defp get_attempt(id) do
    Attempts.get(id,
      include: [workflow: [:triggers, :edges, jobs: [:credential]]]
    )
  end

  defp replace_reason_with_exit_reason(params) do
    {reason, payload} = Map.pop(params, "reason")

    Map.put(
      payload,
      "state",
      case reason do
        "ok" -> :success
        "fail" -> :failed
        "crash" -> :crashed
        "cancel" -> :cancelled
        "kill" -> :killed
        "exception" -> :exception
        unknown -> unknown
      end
    )
  end

  defp update_scrubber(nil, samples, basic_auth) do
    Scrubber.start_link(
      samples: samples,
      basic_auth: basic_auth
    )
  end

  defp update_scrubber(scrubber, samples, basic_auth) do
    :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
    {:ok, scrubber}
  end
end
