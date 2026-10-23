defmodule LightningWeb.AdaptorController do
  @moduledoc """
  Bulk adaptor catalogue for the workflow editor's picker.

  Route: `GET /adaptors/catalogue`. The stamp and the payload it describes
  are cached together by `Lightning.Adaptors.Store.catalogue/1`, so a
  matching `If-None-Match` answers 304 without touching Postgres, and a
  miss on the ETag still serves an already-rendered payload.

  A catalogue that has never loaded answers 503 `not_ready` with a `retry-after`
  rather than an empty list, so the picker shows its retry state instead of no
  adaptors.
  """

  use LightningWeb, :controller

  alias Lightning.Adaptors
  alias LightningWeb.API.Problem

  require Logger

  def index(conn, _params) do
    case Adaptors.catalogue() do
      {:ok, {stamp, entries}} ->
        etag = etag_for(stamp)

        conn =
          conn
          |> put_resp_header("etag", etag)
          |> put_resp_header("cache-control", "private, no-cache")
          |> put_resp_header("vary", "Cookie")

        if get_req_header(conn, "if-none-match") == [etag] do
          send_resp(conn, 304, "")
        else
          json(conn, %{data: entries})
        end

      {:error, reason} ->
        Logger.warning(
          "LightningWeb.AdaptorController: adaptor catalogue unavailable: " <>
            inspect(reason)
        )

        Problem.respond(conn, Problem.new(:not_ready, retry_after: 5))
    end
  end

  defp etag_for({nil, 0}), do: ~s("empty")

  defp etag_for({%DateTime{} = stamp, count}),
    do: ~s("#{DateTime.to_iso8601(stamp)}-#{count}")
end
