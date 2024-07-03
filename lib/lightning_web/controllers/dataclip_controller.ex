defmodule LightningWeb.DataclipController do
  use LightningWeb, :controller

  alias Lightning.DataclipScrubber
  alias Lightning.Invocation
  alias Lightning.Policies.Dataclips
  alias Lightning.Policies.Permissions

  @max_age 86_400

  def show(conn, %{"id" => dataclip_id}) do
    dataclip_without_body = Invocation.get_dataclip!(dataclip_id)

    if Permissions.can?(
         Dataclips,
         :view_dataclip,
         conn.assigns.current_user,
         dataclip_without_body
       ) do
      maybe_respond_with_body(conn, dataclip_without_body)
    else
      conn
      |> put_status(403)
      |> json(%{error: "You are not authorized to view this dataclip."})
    end
  end

  defp maybe_respond_with_body(conn, dataclip) do
    case get_req_header(conn, "if-modified-since") do
      [last_modified] ->
        if dataclip_is_modified?(dataclip, last_modified) do
          respond_with_body(conn, dataclip.id)
        else
          conn |> send_resp(304, "")
        end

      [] ->
        respond_with_body(conn, dataclip.id)
    end
  end

  defp respond_with_body(conn, dataclip_id) do
    dataclip = Invocation.get_dataclip_details!(dataclip_id)

    body =
      DataclipScrubber.scrub_dataclip_body!(%{
        dataclip
        | body: Jason.encode!(dataclip.body, pretty: true)
      })

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("vary", "Accept-Encoding, Cookie")
    |> put_resp_header("cache-control", "private, max-age=#{@max_age}")
    |> put_resp_header("last-modified", to_rfc1123!(dataclip.updated_at))
    |> send_resp(200, body)
  end

  defp dataclip_is_modified?(dataclip, last_modified) do
    case from_rfc1123(last_modified) do
      {:ok, last_modified} ->
        dataclip.updated_at
        |> DateTime.truncate(:second)
        |> DateTime.after?(last_modified)

      _unknown_date ->
        true
    end
  end

  defp to_rfc1123!(datetime) do
    Timex.format!(datetime, "%a, %d %b %Y %H:%M:%S GMT", :strftime)
  end

  defp from_rfc1123(datetime) do
    with {:ok, naive_date} <-
           Timex.parse(datetime, "%a, %d %b %Y %H:%M:%S GMT", :strftime) do
      DateTime.from_naive(naive_date, "Etc/UTC")
    end
  end
end
