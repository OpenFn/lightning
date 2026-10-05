defmodule AdaptorCache.Cache do
  @moduledoc """
  On-disk record-and-replay store.

  A response lives as two sibling files: the raw body, and a `.meta` JSON
  sidecar holding the status, content type and etag. No TTL — once written, a
  file is authoritative until `purge/0` removes it.
  """

  @data_dirs ~w(npm jsdelivr github)

  def root, do: System.get_env("ADAPTOR_CACHE_DIR", "/tmp/adaptor_cache")

  def data_dirs, do: @data_dirs

  def run_dir, do: Path.join(root(), ".run")

  @doc """
  Builds the on-disk path for a request, mirroring its path segments as
  directories so recorded files stay human-navigable and hand-editable. A
  non-empty query string is appended to the leaf filename, with any `/`
  replaced first — unlike a URL path, a query string may legally contain
  unescaped `/` and `..`, so it can't be trusted to stay inside the leaf
  segment.

  Final defense: `Path.expand` the result and verify it's still under
  `root()`. This is what actually blocks traversal (from either the path or
  the query) — the `.`/`..` segment check above is just a fast, readable
  rejection for the common case.
  """
  def key_path(prefix, path, query) when prefix in @data_dirs do
    segments = path |> String.trim_leading("/") |> String.split("/")

    if Enum.any?(segments, &(&1 in [".", ".."])) or
         Enum.any?(segments, &(&1 == "")) do
      {:error, :invalid_path}
    else
      safe_query = String.replace(query || "", "/", "%2F")

      leaf =
        if safe_query == "",
          do: List.last(segments),
          else: List.last(segments) <> "?" <> safe_query

      dirs = Enum.slice(segments, 0..-2//1)
      root = Path.expand(root())
      file = Path.expand(Path.join([root, prefix] ++ dirs ++ [leaf]))

      if String.starts_with?(file, root <> "/"),
        do: {:ok, file},
        else: {:error, :invalid_path}
    end
  end

  def read(file) do
    with true <- File.regular?(file),
         {:ok, meta_json} <- File.read(file <> ".meta"),
         {:ok, meta} <- JSON.decode(meta_json),
         {:ok, body} <- File.read(file) do
      {:ok,
       %{
         status: meta["status"],
         content_type: meta["content_type"],
         etag: meta["etag"],
         body: body
       }}
    else
      _ -> :miss
    end
  end

  def write(file, status, content_type, etag, body) do
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, body)

    File.write!(
      file <> ".meta",
      JSON.encode!(%{status: status, content_type: content_type, etag: etag})
    )

    :ok
  end

  @doc "Wipes recorded responses, leaving the daemon's pidfile/log (under `.run/`) intact."
  def purge do
    Enum.each(@data_dirs, &File.rm_rf!(Path.join(root(), &1)))
    :ok
  end
end
