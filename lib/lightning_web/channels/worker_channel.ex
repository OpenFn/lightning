defmodule LightningWeb.WorkerChannel do
  @moduledoc """
  Websocket channel to handle when workers join or claim something to run.
  """
  use LightningWeb, :channel

  alias Lightning.Attempts
  alias Lightning.Workers

  @impl true
  def join("worker:queue", _payload, %{assigns: %{token: token}} = socket) do
    case Workers.verify_worker_token(token) do
      {:ok, claims} ->
        {:ok, assign(socket, :claims, claims)}

      {:error, _} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def join("worker:queue", _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("claim", %{"demand" => demand}, socket) do
    case Attempts.claim(demand) do
      {:ok, attempts} ->
        attempts =
          attempts
          |> Enum.map(fn attempt ->
            token = Lightning.Workers.generate_attempt_token(attempt)

            %{
              "id" => attempt.id,
              "token" => token
            }
          end)

        {:reply, {:ok, %{attempts: attempts}}, socket}

      {:error, changeset} ->
        {:reply, {:error, LightningWeb.ChangesetJSON.error(changeset)}, socket}
    end
  end
end
