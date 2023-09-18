defmodule LightningWeb.AttemptChannel do
  alias Lightning.Attempts
  use LightningWeb, :channel

  @impl true
  def join("worker:queue", _payload, socket) do
    if authorized?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
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

  defp authorized?(socket) do
    not is_nil(socket.assigns[:claims])
  end
end
