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
         attempt when is_map(attempt) <- get_attempt(id) || {:error, :not_found} do
      {:ok, socket |> assign(%{claims: claims, id: id, attempt: attempt})}
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

  def handle_in("fetch:dataclip", _, socket) do
    body =
      Attempts.get_dataclip(socket.assigns.attempt)
      |> Jason.Fragment.new()
      |> Phoenix.json_library().encode_to_iodata!()

    {:reply, {:ok, {:binary, body}}, socket}
  end

  def handle_in("run:start", payload, socket) do
    Attempts.start_run(
      %{"attempt_id" => socket.assigns.attempt.id}
      |> Enum.into(payload)
    )
    |> case do
      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}

      {:ok, run} ->
        {:reply, {:ok, %{run: run}}, socket}
    end
  end

  defp get_attempt(id) do
    Attempts.get(id, include: [workflow: [:triggers, :jobs, :edges]])
  end
end
