defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.{Jobs, Invocation, Pipeline}

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
            %{job_id: job.id, project_id: job.project_id, type: :webhook},
            %{type: :http_request, body: conn.body_params}
          )

        Task.start(Pipeline, :process, [event])

        conn
        |> json(%{event_id: event.id, run_id: run.id})
    end
  end
end
