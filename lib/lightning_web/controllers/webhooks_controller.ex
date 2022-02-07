defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.{Jobs, Invocation}

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => path}) do
    path
    |> Enum.join("/")
    |> Jobs.get_job_by_webhook()
    |> case do
      nil ->
        put_status(conn, :not_found)
        |> json(%{})

      job ->
        {:ok, %{event: event, run: run}} =
          Invocation.create(
            %{job_id: job.id, type: :webhook},
            %{type: :http_request, body: conn.body_params}
          )

        conn
        |> json(%{event_id: event.id, run_id: run.id})
    end
  end
end
