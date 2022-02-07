defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Jobs

  def create(conn, %{"path" => path}) do
    path
    |> Enum.join("/")
    |> Jobs.get_job_by_webhook()
    |> case do
      nil ->
        put_status(conn, :not_found)

      _job ->
        conn
    end
    |> json(%{foo: "bar"})
  end
end
