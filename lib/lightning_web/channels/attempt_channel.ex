defmodule LightningWeb.RunChannel do
  @moduledoc """
  Phoenix channel to interact with Runs.
  """
  use LightningWeb, :channel

  alias Lightning.Runs
  alias Lightning.Credentials
  alias Lightning.Repo
  alias Lightning.Scrubber
  alias Lightning.Workers
  alias LightningWeb.RunJson

  require Jason.Helpers
  require Logger

  @impl true
  def join(
        "run:" <> id,
        %{"token" => token},
        %{assigns: %{token: worker_token}} = socket
      ) do
    with {:ok, _} <- Workers.verify_worker_token(worker_token),
         {:ok, claims} <- Workers.verify_run_token(token, %{id: id}),
         run when is_map(run) <- get_run(id) || {:error, :not_found},
         project_id when is_binary(project_id) <-
           Runs.get_project_id_for_run(run) do
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

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join("run:" <> _, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("fetch:run", _, socket) do
    {:reply, {:ok, RunJson.render(socket.assigns.run)}, socket}
  end

  # TODO - Taylor to remove this once the migration is complete
  def handle_in("attempt:start", payload, socket) do
    worker_upgrade_required("v0.8.0")
    handle_in("run:start", rename_run_id(payload), socket)
  end

  def handle_in("run:start", _, socket) do
    socket.assigns.run
    |> Runs.start_run()
    |> case do
      {:ok, run} ->
        {:reply, {:ok, nil}, socket |> assign(run: run)}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}
    end
  end

  # TODO - Taylor to remove this once the migration is complete
  def handle_in("attempt:complete", payload, socket) do
    worker_upgrade_required("v0.7.0")
    handle_in("run:complete", rename_run_id(payload), socket)
  end

  def handle_in("run:complete", payload, socket) do
    params =
      payload |> replace_reason_with_exit_reason()

    socket.assigns.run
    |> Runs.complete_run(params)
    |> case do
      {:ok, run} ->
        # TODO: Turn FailureAlerter into an Oban worker and process async
        # instead of blocking the channel.
        run
        |> Repo.preload([:log_lines, work_order: [:workflow]])
        |> Lightning.FailureAlerter.alert_on_failure()

        {:reply, {:ok, nil}, socket |> assign(run: run)}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}
    end
  end

  def handle_in("fetch:credential", %{"id" => id}, socket) do
    %{run: run, scrubber: scrubber} = socket.assigns

    with credential <- Runs.get_credential(run, id) || :not_found,
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
  preformatted for use as "initial state" in a run.

  This means that the body of http requests will be nested inside a "data" key.

  There is an open discussion on the community that may impact how we
  store HTTP requests in the database as dataclips and how we send the body
  of those HTTP requests to the worker to use as initial state.
  """
  def handle_in("fetch:dataclip", _, socket) do
    body = Runs.get_input(socket.assigns.run)

    {:reply, {:ok, {:binary, body}}, socket}
  end

  def handle_in("step:start", payload, socket) do
    Map.get(payload, "job_id", :missing_job_id)
    |> case do
      job_id when is_binary(job_id) ->
        %{"run_id" => socket.assigns.run.id}
        |> Enum.into(payload)
        |> Runs.start_step()
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

  def handle_in("step:complete", payload, socket) do
    %{
      "run_id" => socket.assigns.run.id,
      "project_id" => socket.assigns.project_id
    }
    |> Enum.into(payload)
    |> Runs.complete_step()
    |> case do
      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}

      {:ok, step} ->
        {:reply, {:ok, %{step_id: step.id}}, socket}
    end
  end

  def handle_in("run:log", payload, socket) do
    %{run: run, scrubber: scrubber} = socket.assigns

    Runs.append_run_log(run, rename_run_id(payload), scrubber)
    |> case do
      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}

      {:ok, log_line} ->
        {:reply, {:ok, %{log_line_id: log_line.id}}, socket}
    end
  end

  defp get_run(id) do
    Runs.get(id,
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
