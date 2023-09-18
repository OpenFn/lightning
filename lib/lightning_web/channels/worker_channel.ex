defmodule LightningWeb.WorkerChannel do
  alias Lightning.{Workers, Attempts}
  use LightningWeb, :channel

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
    attempts =
      Attempts.claim(demand)
      |> then(fn {:ok, attempts} ->
        attempts
        |> Enum.map(fn attempt ->
          token = Lightning.Workers.generate_attempt_token(attempt)

          %{
            "id" => attempt.id,
            "token" => token
          }
        end)
      end)

    {:reply, {:ok, %{attempts: attempts}}, socket}
  end
end
