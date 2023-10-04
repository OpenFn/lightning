defmodule LightningWeb.AttemptChannel do
  alias Lightning.{Workers, Attempts}
  alias LightningWeb.AttemptJson
  use LightningWeb, :channel

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
         project_id: project_id
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
    Attempts.complete_attempt(
      socket.assigns.attempt,
      payload |> Map.get("status")
    )
    |> case do
      {:ok, attempt} ->
        {:reply, {:ok, nil}, socket |> assign(attempt: attempt)}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}
    end
  end

  def handle_in("fetch:attempt", _, socket) do
    {:reply, {:ok, AttemptJson.render(socket.assigns.attempt)}, socket}
  end

  def handle_in("fetch:dataclip", _, socket) do
    body =
      Attempts.get_dataclip_body(socket.assigns.attempt)
      |> Jason.Fragment.new()
      |> Phoenix.json_library().encode_to_iodata!()

    {:reply, {:ok, {:binary, body}}, socket}
  end

  def handle_in("run:start", payload, socket) do
    %{"attempt_id" => socket.assigns.attempt.id}
    |> Enum.into(payload)
    |> Attempts.start_run()
    |> case do
      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}

      {:ok, run} ->
        {:reply, {:ok, %{run_id: run.id}}, socket}
    end
  end

  def handle_in("run:complete", payload, socket) do
    %{
      "attempt_id" => socket.assigns.attempt.id,
      "project_id" => socket.assigns.project_id
    }
    |> Enum.into(payload)
    |> Attempts.complete_run()
    |> case do
      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}

      {:ok, run} ->
        {:reply, {:ok, %{run_id: run.id}}, socket}
    end
  end

  defp get_attempt(id) do
    Attempts.get(id, include: [workflow: [:triggers, :jobs, :edges]])
  end
end
