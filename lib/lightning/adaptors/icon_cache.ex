defmodule Lightning.Adaptors.IconCache do
  @moduledoc """
  Pure filesystem helper owning the on-disk adaptor icon cache.

  Not a GenServer. Three stateless functions over
  `Lightning.Adaptors.Config.icon_path/0`, which returns `ADAPTORS_ICONS_PATH`
  when set and otherwise resolves the `{:tmp, suffix}` default at call time.

  Disk layout is **source-partitioned** and **content-addressed**:

      <Config.icon_path/0>/<source>/<name>/<shape>.<sha8>.<ext>

  where `sha8` is the first 8 lowercase hex characters of the icon
  sha256 on the adaptor row. Source partitioning means flipping
  `ADAPTORS_STRATEGY` between restarts cannot accidentally serve `:npm`
  bytes from a row that's now resolved via `:local` (or vice versa).
  Putting the sha in the filename means `cached?/5` is a plain
  existence check, and a node holding an earlier icon simply misses and
  refetches instead of serving it forever; `write!/6` removes the
  superseded siblings for that shape.

  Concurrent first-request fetchers are coalesced upstream by Cachex's
  courier on `{:icon_bytes, source, name, shape}` inside
  `Lightning.Adaptors.Store.icon/3`, and all in-flight peers receive the
  courier's result for free. Bytes that verify are left uncommitted,
  since this directory is their cache, but bytes that disagree with the
  row's sha or extension are committed as an error, so the disagreement
  is not re-fetched from the source on every request until the row moves.
  The temp-then-rename in `write!/6` is the belt-and-braces guarantee
  for the file-write step itself: readers never observe a half-written
  file.
  """

  alias Lightning.Adaptors.Config
  alias Lightning.Adaptors.PackageName

  @type source :: :npm | :local
  @type name :: String.t()
  @type shape :: :square | :rectangle
  @type ext :: String.t()

  @doc """
  Disk path for an icon. Nothing is created.

  `name` may contain a `/` (scoped npm packages like
  `@openfn/language-foo`); `Path.join/1` preserves the slash so the
  scope becomes a real subdirectory.

  Raises `ArgumentError` on a name `PackageName` would reject. Icons are
  written straight from a strategy's response, before the row reaches
  `CatalogueAdaptor.changeset/2` and its name validation, so this is the
  only thing standing between a hostile registry entry and a write
  outside the cache root.
  """
  @spec path(source(), name(), shape(), ext(), binary()) :: Path.t()
  def path(source, name, shape, ext, sha256) do
    unless Regex.match?(PackageName.name_format(), name) do
      raise ArgumentError,
            "unsafe adaptor name for an icon path: #{inspect(name)}"
    end

    Path.join([
      Config.icon_path(),
      to_string(source),
      name,
      "#{shape}.#{sha8(sha256)}.#{ext}"
    ])
  end

  @doc """
  Whether the icon for `sha256` is on disk. The sha is part of the
  filename, so existence is the whole check.
  """
  @spec cached?(source(), name(), shape(), ext(), binary()) :: boolean()
  def cached?(source, name, shape, ext, sha256) do
    File.exists?(path(source, name, shape, ext, sha256))
  end

  @doc """
  Atomically write `bytes` for `sha256` and return the path written.

  The write is staged in a sibling temp file and then renamed into
  place, so concurrent readers never observe a half-written file. Any
  superseded file for the same shape, whatever its extension or
  pre-sha naming, is removed first, so a rename never lands on a
  directory left empty by its own sweep.
  """
  # Every path here comes from `path/5`, which rejects a name that is not
  # a safe path segment, so nothing escapes `Config.icon_path/0`.
  # sobelow_skip ["Traversal.FileModule"]
  @spec write!(source(), name(), shape(), ext(), binary(), binary()) ::
          Path.t()
  def write!(source, name, shape, ext, bytes, sha256) when is_binary(bytes) do
    final_path = path(source, name, shape, ext, sha256)
    dir = Path.dirname(final_path)
    File.mkdir_p!(dir)

    temp_path =
      Path.join(dir, ".#{Path.basename(final_path)}.#{random_suffix()}.tmp")

    try do
      File.write!(temp_path, bytes)
      remove_superseded(dir, shape, final_path)
      File.rename!(temp_path, final_path)
    rescue
      e ->
        _ = File.rm(temp_path)
        reraise e, __STACKTRACE__
    end

    final_path
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp remove_superseded(dir, shape, final_path) do
    dir
    |> Path.join("#{shape}.*")
    |> Path.wildcard()
    |> Enum.reject(&(&1 == final_path))
    |> Enum.each(&File.rm/1)
  end

  defp sha8(sha256) when is_binary(sha256) do
    sha256 |> Base.encode16(case: :lower) |> binary_part(0, 8)
  end

  @spec random_suffix() :: String.t()
  defp random_suffix do
    8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
