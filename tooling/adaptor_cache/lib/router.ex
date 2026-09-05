defmodule AdaptorCache.Router do
  @moduledoc """
  Record-and-replay reverse proxy for the three upstreams
  `Lightning.Adaptors.NPM` reads from. A hit is served straight off disk; a
  miss is fetched live (following redirects itself, so the *final* resource
  is what gets cached under the *originally requested* key), recorded, then
  served.
  """
  use Plug.Router

  alias AdaptorCache.Cache

  plug :match
  plug :dispatch

  @upstreams %{
    "npm" => "https://registry.npmjs.org",
    "jsdelivr" => "https://cdn.jsdelivr.net",
    "github" => "https://raw.githubusercontent.com"
  }

  get "/_healthz" do
    send_resp(conn, 200, "ok\n")
  end

  get("/npm/*rest", do: proxy(conn, "npm", rest))
  get("/jsdelivr/*rest", do: proxy(conn, "jsdelivr", rest))
  get("/github/*rest", do: proxy(conn, "github", rest))

  match _ do
    send_resp(conn, 404, "adaptor_cache: use /npm/, /jsdelivr/ or /github/\n")
  end

  defp proxy(conn, prefix, rest_segments) do
    path = "/" <> Enum.join(rest_segments, "/")
    query = conn.query_string

    case Cache.key_path(prefix, path, query) do
      {:error, :invalid_path} ->
        send_resp(conn, 400, "adaptor_cache: invalid path\n")

      {:ok, file} ->
        case Cache.read(file) do
          {:ok, resp} ->
            respond(conn, resp, "HIT")

          :miss ->
            fetch_and_record(conn, file, prefix, path, query)
        end
    end
  end

  defp fetch_and_record(conn, file, prefix, path, query) do
    url =
      @upstreams[prefix] <> path <> if(query == "", do: "", else: "?" <> query)

    case Req.get(url,
           redirect: true,
           decode_body: false,
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
        content_type =
          header(headers, "content-type") || "application/octet-stream"

        etag = header(headers, "etag")

        # Only 2xx and 404 are content worth freezing forever. Everything
        # else (5xx, and npm's 429 rate-limit) is transient upstream
        # trouble — recording it would mean a rate-limit sticks until
        # someone runs `purge`. 404 is kept deliberately: github.ex's
        # png-then-svg fallback and the "adaptor disappeared" scenario both
        # rely on it being cacheable.
        if status in 200..299 or status == 404,
          do: Cache.write(file, status, content_type, etag, body)

        respond(
          conn,
          %{status: status, content_type: content_type, etag: etag, body: body},
          "MISS"
        )

      {:error, reason} ->
        log(conn, 502, "ERROR")

        send_resp(
          conn,
          502,
          "adaptor_cache: upstream error: #{inspect(reason)}\n"
        )
    end
  end

  defp respond(conn, resp, cache_status) do
    log(conn, resp.status, cache_status)

    conn
    # put_resp_content_type/2 always appends "; charset=utf-8", which
    # duplicates one the upstream already sent — set the header directly to
    # replay it byte-for-byte instead.
    |> put_resp_header("content-type", resp.content_type)
    |> put_resp_header("x-cache-status", cache_status)
    |> maybe_put_etag(resp.etag)
    |> send_resp(resp.status, resp.body)
  end

  defp maybe_put_etag(conn, nil), do: conn
  defp maybe_put_etag(conn, etag), do: put_resp_header(conn, "etag", etag)

  defp header(headers, name), do: headers |> Map.get(name, []) |> List.first()

  defp log(conn, status, cache_status) do
    uri =
      if conn.query_string == "",
        do: conn.request_path,
        else: conn.request_path <> "?" <> conn.query_string

    # Strip control chars (a crafted request path could otherwise inject
    # ANSI escapes into whatever terminal is tailing this with `logs`).
    uri = String.replace(uri, ~r/[\x00-\x1f\x7f]/, "")

    IO.puts(
      "#{DateTime.utc_now() |> DateTime.to_iso8601()} status=#{status} cache=#{cache_status} GET #{uri}"
    )
  end
end
