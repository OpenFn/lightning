defmodule AdaptorCache.Publish do
  @moduledoc """
  `publish <name> <version>` — makes both scenarios (new adaptor, new
  version) reproducible in one step by always updating the recorded npm
  search response and packument together.

  `scheduler.ex`'s `fetch_if_changed/4` only fetches a packument when the
  search response's `latest_version` for that package differs from the DB —
  so a packument-only bump is a silent no-op. This module never lets the two
  drift apart: both updates are computed before either is written, so a
  malformed hand-edited fixture fails before touching disk instead of
  leaving one file updated and the other stale.
  """

  alias AdaptorCache.Cache

  # registry.ex builds this with `query: [text: "@openfn", size: 250]`, and
  # Tesla's default www-form query encoding percent-encodes `@` — the wire
  # query is "text=%40openfn&size=250", not the literal text. Not templated
  # per package, so it's still the one deterministic key for "the" recorded
  # search response.
  @search_query "text=%40openfn&size=250"

  def run(name, version) do
    packument_file = key_path!("npm", "/" <> name, "")
    search_file = key_path!("npm", "/-/v1/search", @search_query)

    with {:ok, packument} <- update_packument(packument_file, name, version),
         {:ok, search} <- update_search(search_file, name, version) do
      Cache.write(
        packument_file,
        200,
        "application/json",
        nil,
        JSON.encode!(packument)
      )

      Cache.write(
        search_file,
        200,
        "application/json",
        nil,
        JSON.encode!(search)
      )

      :ok
    end
  end

  defp key_path!(prefix, path, query) do
    {:ok, file} = Cache.key_path(prefix, path, query)
    file
  end

  defp update_packument(file, name, version) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

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

    with {:ok, existing} <- decode_cached(file) do
      packument =
        case existing do
          :miss ->
            %{
              "name" => name,
              "dist-tags" => %{"latest" => version},
              "versions" => %{version => version_entry},
              "time" => %{version => now}
            }

          packument ->
            # Map.update/4 only falls back to the default when the key is
            # *absent* — a hand-edited "versions": null still passes nil to
            # the updater, so each field guards with `|| %{}` the same way.
            packument
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

      {:ok, packument}
    end
  end

  defp update_search(file, name, version) do
    minimal_entry = %{"package" => %{"name" => name, "version" => version}}

    with {:ok, existing} <- decode_cached(file) do
      search =
        case existing do
          :miss ->
            %{
              "objects" => [minimal_entry],
              "total" => 1,
              "time" => DateTime.utc_now() |> DateTime.to_iso8601()
            }

          search ->
            objects = search["objects"] || []

            objects =
              if Enum.any?(objects, &(&1["package"]["name"] == name)) do
                # Only bump the version field, so a real recorded entry's
                # other fields (maintainers, license, downloads, ...)
                # survive intact.
                Enum.map(objects, fn
                  %{"package" => %{"name" => ^name}} = object ->
                    put_in(object, ["package", "version"], version)

                  other ->
                    other
                end)
              else
                objects ++ [minimal_entry]
              end

            search
            |> Map.put("objects", objects)
            |> Map.put("total", length(objects))
        end

      {:ok, search}
    end
  end

  # README.md explicitly invites hand-editing these files, so malformed JSON
  # is expected input, not an exceptional one — fail with a message naming
  # the file, not a bare JSON.DecodeError stacktrace.
  defp decode_cached(file) do
    case Cache.read(file) do
      {:ok, %{body: body}} ->
        case JSON.decode(body) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, reason} ->
            {:error,
             "#{file} is not valid JSON (#{inspect(reason)}) — fix it or purge"}
        end

      :miss ->
        {:ok, :miss}
    end
  end

  defp basename(name), do: name |> String.split("/") |> List.last()
end
