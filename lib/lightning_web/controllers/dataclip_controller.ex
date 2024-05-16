defmodule LightningWeb.DataclipController do
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.DataclipScrubber

  def show(conn, %{"id" => dataclip_id}) do
    dataclip = Invocation.get_dataclip_details!(dataclip_id)

    body =
      DataclipScrubber.scrub_dataclip_body!(%{
        dataclip
        | body: Jason.encode!(dataclip.body, pretty: true)
      })

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
