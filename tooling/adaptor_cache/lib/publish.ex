defmodule AdaptorCache.Publish do
  @moduledoc """
  `publish <name> <version>` — makes both scenarios (new adaptor, new
  version) reproducible in one step by updating, together, the three npm
  responses `Lightning.Adaptors.NPM.Registry` reads: the scope's name list,
  the search response, and the package's own packument.

  Each of the three starts from what's recorded; anything not recorded yet
  is fetched from npm and recorded first, so publishing never replaces a
  real response with a synthetic one holding a single version. The only
  exception is a 404 packument, which is npm saying the package is genuinely
  new.

  `scheduler.ex`'s `fetch_if_changed/4` only fetches a packument when the
  search response's `latest_version` for that package differs from the DB —
  so a packument-only bump is a silent no-op. All three updates are worked
  out before any of them is written, so a malformed hand-edited fixture or an
  unreachable npm leaves the new version out of all three rather than in one
  and missing from the others.
  """

  alias AdaptorCache.Cache
  alias AdaptorCache.Router

  # registry.ex builds this with `query: [text: "@openfn", size: 250]`, and
  # Tesla's default www-form query encoding percent-encodes `@` — the wire
  # query is "text=%40openfn&size=250", not the literal text. Not templated
  # per package, so it's still the one deterministic key for "the" recorded
  # search response.
  @search_query "text=%40openfn&size=250"
  @names_path "/-/user/openfn/package"

  def run(name, version) do
    with {:ok, packument_file, packument} <- load("/" <> name, "", :new_if_404),
         {:ok, names_file, names} <- load(@names_path, ""),
         {:ok, search_file, search} <- load("/-/v1/search", @search_query) do
      write(packument_file, add_version(packument, name, version))
      # registry.ex only trusts names that appear on this list, so a package
      # missing from it stays invisible to Lightning however complete its
      # packument is. "write" is the access level npm reports for the org's
      # own packages.
      write(names_file, Map.put_new(names, name, "write"))
      write(search_file, upsert_search(search, name, version))
      :ok
    end
  end

  defp write(file, body),
    do: Cache.write(file, 200, "application/json", nil, JSON.encode!(body))

  # Prefer whatever is already recorded. Otherwise fetch npm's real response
  # and record it first, so the update is added to the real thing instead of
  # replacing it.
  defp load(path, query, on_404 \\ :error) do
    {:ok, file} = Cache.key_path("npm", path, query)

    case Cache.read(file) do
      {:ok, %{body: body}} ->
        with {:ok, decoded} <- decode(file, body), do: {:ok, file, decoded}

      :miss ->
        with {:ok, fetched} <- fetch(path, query, on_404) do
          unless fetched == %{},
            do:
              Cache.write(
                file,
                200,
                "application/json",
                nil,
                JSON.encode!(fetched)
              )

          {:ok, file, fetched}
        end
    end
  end

  defp fetch(path, query, on_404) do
    url =
      Router.upstream("npm") <>
        path <> if(query == "", do: "", else: "?" <> query)

    case Req.get(url, redirect: true, retry: false, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} when on_404 == :new_if_404 ->
        {:ok, %{}}

      other ->
        {:error,
         "couldn't fetch #{path} from npm (#{describe(other)}) — check your connection, or run a refresh through the proxy first"}
    end
  end

  defp describe({:ok, %Req.Response{status: status}}), do: "HTTP #{status}"
  defp describe({:error, reason}), do: inspect(reason)

  defp add_version(packument, name, version) do
    version_entry = %{
      "dist" => %{
        "tarball" =>
          "https://registry.npmjs.org/#{name}/-/#{basename(name)}-#{version}.tgz",
        "integrity" => "sha512-adaptorcache",
        "unpackedSize" => 0
      },
      "dependencies" => %{},
      "peerDependencies" => %{}
    }

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Map.update/4 only falls back to the default when the key is *absent* —
    # a hand-edited "versions": null still passes nil to the updater, so each
    # field guards with `|| %{}` the same way.
    packument
    |> Map.put("name", name)
    |> Map.put(
      "dist-tags",
      Map.put(packument["dist-tags"] || %{}, "latest", version)
    )
    |> Map.put(
      "versions",
      Map.put(packument["versions"] || %{}, version, version_entry)
    )
    |> Map.put("time", Map.put(packument["time"] || %{}, version, now))
  end

  defp upsert_search(search, name, version) do
    objects = search["objects"] || []

    objects =
      if Enum.any?(objects, &(&1["package"]["name"] == name)) do
        # Only bump the version field, so a real recorded entry's other
        # fields (maintainers, license, downloads, ...) survive intact.
        Enum.map(objects, fn
          %{"package" => %{"name" => ^name}} = object ->
            put_in(object, ["package", "version"], version)

          other ->
            other
        end)
      else
        objects ++ [%{"package" => %{"name" => name, "version" => version}}]
      end

    search
    |> Map.put("objects", objects)
    |> Map.put("total", length(objects))
  end

  # README.md explicitly invites hand-editing these files, so malformed JSON
  # is expected input, not an exceptional one — fail with a message naming
  # the file, not a bare JSON.DecodeError stacktrace.
  defp decode(file, body) do
    case JSON.decode(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        {:error,
         "#{file} is not valid JSON (#{inspect(reason)}) — fix it or purge"}
    end
  end

  defp basename(name), do: name |> String.split("/") |> List.last()
end
