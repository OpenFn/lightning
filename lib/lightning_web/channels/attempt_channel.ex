defmodule LightningWeb.AttemptChannel do
  @moduledoc """
  Phoenix channel to interact with Attempts.
  """
  use LightningWeb, :channel

  alias Lightning.Attempts
  alias Lightning.Credentials
  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.Scrubber
  alias Lightning.Workers
  alias LightningWeb.RunWithOptions
  alias LightningWeb.RunOptions

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
         scrubber: nil,
         retention_policy: Projects.project_retention_policy_for(attempt)
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
  def handle_in("fetch:attempt", _, %{assigns: assigns} = socket) do
    options = %RunOptions{
      output_dataclips: include_output_dataclips?(assigns.retention_policy)
    }

    {:reply, {:ok, RunWithOptions.render(assigns.attempt, options)}, socket}
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
    body = Attempts.get_input(socket.assigns.attempt)

    if socket.assigns.retention_policy == :erase_all do
      Attempts.wipe_dataclips(socket.assigns.attempt)
    end

    {:reply, {:ok, {:binary, body}}, socket}
  end

  # TODO - Taylor to remove this once the migration is complete
  def handle_in("run:start", payload, socket) do
    worker_upgrade_required("v0.7.0")
    handle_in("step:start", rename_run_id(payload), socket)
  end

  def handle_in("step:start", payload, socket) do
    Map.get(payload, "job_id", :missing_job_id)
    |> case do
      job_id when is_binary(job_id) ->
        %{"attempt_id" => socket.assigns.attempt.id}
        |> Enum.into(payload)
        |> maybe_drop_dataclip(socket.assigns.retention_policy)
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

  # TODO - Taylor to remove this once the migration is complete
  def handle_in("run:complete", payload, socket) do
    worker_upgrade_required("v0.7.0")
    handle_in("step:complete", rename_run_id(payload), socket)
  end

  def handle_in("step:complete", payload, socket) do
    %{
      "attempt_id" => socket.assigns.attempt.id,
      "project_id" => socket.assigns.project_id
    }
    |> Enum.into(payload)
    |> maybe_drop_dataclip(socket.assigns.retention_policy)
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

    Attempts.append_attempt_log(attempt, rename_run_id(payload), scrubber)
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

  defp include_output_dataclips?(retention_policy) do
    retention_policy != :erase_all
  end

  defp maybe_drop_dataclip(params, retention_policy) do
    if retention_policy == :erase_all do
      Map.drop(params, [
        "output_dataclip",
        "output_dataclip_id",
        "input_dataclip_id"
      ])
    else
      params
    end
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

  # TODO - Taylor to remove this once the migration is complete
  defp worker_upgrade_required(v),
    do:
      Logger.warning("Please upgrade your connect ws-worker to #{v} or greater")

  # TODO - Taylor to remove this once the migration is complete
  defp rename_run_id(%{"run_id" => id} = map) do
    Map.delete(map, "run_id")
    |> Map.put("step_id", id)
  end

  defp rename_run_id(any), do: any
end
