defmodule LightningWeb.DataclipController do
  use LightningWeb, :controller

  alias Lightning.DataclipScrubber
  alias Lightning.Invocation
  alias Lightning.Policies.Dataclips
  alias Lightning.Policies.Permissions
  alias Lightning.Repo

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
    import Ecto.Query

    # Query body as JSON text directly from PostgreSQL, avoiding expensive
    # deserialization to Elixir map (saves ~38x memory amplification!)
    result =
      from(d in Lightning.Invocation.Dataclip,
        where: d.id == ^dataclip_id,
        select: %{
          body_json: fragment("?::text", d.body),
          type: d.type,
          id: d.id,
          updated_at: d.updated_at
        }
      )
      |> Repo.one!()

    # Only scrub step_result dataclips (most don't need scrubbing)
    body =
      if result.type == :step_result do
        # For step_result, we need to scrub credentials
        # Pass a minimal struct with just what scrubber needs
        dataclip_for_scrubbing = %{
          body: result.body_json,
          type: result.type,
          id: result.id
        }
        DataclipScrubber.scrub_dataclip_body!(dataclip_for_scrubbing)
      else
        # No scrubbing needed - return JSON text directly
        result.body_json
      end

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("vary", "Accept-Encoding, Cookie")
    |> put_resp_header("cache-control", "private, max-age=#{@max_age}")
    |> put_resp_header("last-modified", to_rfc1123!(result.updated_at))
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
