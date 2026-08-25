defmodule LightningWeb.AdaptorController do
  @moduledoc """
  Bulk adaptor catalogue for the workflow editor's picker.

  Route: `GET /adaptors/catalogue`. A matching `If-None-Match` returns
  304 before the catalogue query or payload build runs — see
  `Lightning.Adaptors.catalogue_stamp/0`.
  """

  use LightningWeb, :controller

  alias Lightning.Adaptors
  alias LightningWeb.AdaptorIconURL

  def index(conn, _params) do
    etag = etag_for(Adaptors.catalogue_stamp())

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "private, no-cache")
      |> put_resp_header("vary", "Cookie")

    if get_req_header(conn, "if-none-match") == [etag] do
      send_resp(conn, 304, "")
    else
      json(conn, %{data: Enum.map(Adaptors.catalogue(), &render_entry/1)})
    end
  end

  defp render_entry(entry) do
    %{
      name: entry.name,
      latest_version: entry.latest_version,
      versions: entry.versions,
      repository: entry.repository,
      icon_urls: %{
        square: AdaptorIconURL.build(entry.name, entry, :square),
        rectangle: AdaptorIconURL.build(entry.name, entry, :rectangle)
      }
    }
  end

  defp etag_for({nil, 0}), do: ~s("empty")

  defp etag_for({%DateTime{} = stamp, count}),
    do: ~s("#{DateTime.to_iso8601(stamp)}-#{count}")
end
