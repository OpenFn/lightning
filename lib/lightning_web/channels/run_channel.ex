defmodule LightningWeb.RunChannel do
  @moduledoc """
  Phoenix channel to interact with Runs.
  """
  use LightningWeb, :channel

  import LightningWeb.ChannelHelpers

  alias Lightning.Credentials
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
        run
        |> Repo.preload([:log_lines, work_order: [:workflow]])
        |> Lightning.FailureAlerter.alert_on_failure()

        socket |> assign(run: run) |> reply_with({:ok, nil})

      {:error, changeset} ->
        reply_with(socket, {:error, changeset})
    end
  end

  def handle_in("fetch:credential", %{"id" => id}, socket) do
    %{run: run, scrubber: scrubber} = socket.assigns

    with credential when is_map(credential) <-
           Runs.get_credential(run, id) || :not_found,
         {:ok, credential} <- Credentials.maybe_refresh_token(credential),
         samples <- Credentials.sensitive_values_for(credential),
         basic_auth <- Credentials.basic_auth_for(credential),
         {:ok, scrubber} <- update_scrubber(scrubber, samples, basic_auth) do
      socket
      |> assign(scrubber: scrubber)
      |> reply_with({:ok, remove_empty_values(credential.body)})
    else
      :not_found ->
        reply_with(socket, {:error, %{errors: %{id: ["Credential not found!"]}}})

      {:error,
       %{
         body: %{
           "error" => error,
           "error_description" => error_description
         }
       }} ->
        reply_with(socket, {
          :error,
          %{errors: %{id: ["#{inspect(error)}: #{inspect(error_description)}"]}}
        })

      {:error, error} ->
        Logger.error(fn ->
          """
          Something went wrong when fetching or refreshing a credential.

          #{inspect(error)}
          """
        end)

        reply_with(
          socket,
          {:error,
           %{errors: "Something went wrong when retrieving the credential"}}
        )
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
    %{run: run, scrubber: scrubber} = socket.assigns

    case Runs.append_run_log(run, payload, scrubber) do
      {:error, changeset} ->
        reply_with(socket, {:error, changeset})

      {:ok, log_line} ->
        reply_with(socket, {:ok, %{log_line_id: log_line.id}})
    end
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

  defp remove_empty_values(credential_body) do
    Map.reject(credential_body, fn {_key, val} -> val == "" end)
  end
end
