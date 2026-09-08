defmodule Lightning.Adaptors.IconCache do
  @moduledoc """
  Pure filesystem helper owning the on-disk adaptor icon cache.

  Not a GenServer. Three stateless functions over
  `Lightning.Adaptors.Config.icon_path/0`, which returns `ADAPTORS_ICONS_PATH`
  when set and otherwise resolves the `{:tmp, suffix}` default at call time.

  Disk layout is **source-partitioned** and **latest-only**:

      <Config.icon_path/0>/<source>/<name>/<shape>.<ext>

  Source partitioning means flipping `ADAPTORS_STRATEGY` between restarts
  cannot accidentally serve `:npm` bytes from a row that's now resolved
  via `:local` (or vice versa). Latest-only means a subsequent
  `write!/5` for the same key overwrites, and `cached?/5` only trusts a
  file whose bytes still hash to the sha on the adaptor row, so a node
  that cached an earlier icon refetches instead of serving it forever.

  Concurrent first-request fetchers are coalesced upstream by Cachex's
  courier on `{:icon_bytes, source, name, shape}` inside
  `Lightning.Adaptors.Store.icon/3`, and all in-flight peers receive the
  courier's result for free. Bytes that verify are left uncommitted —
  this directory is their cache — but bytes that disagree with the row's
  sha or extension are committed as an error, so the disagreement is not
  re-fetched from the source on every request until the row moves.
  The temp-then-rename in `write!/5` is the belt-and-
  braces guarantee for the file-write step itself: readers never observe
  a half-written file.
  """

  alias Lightning.Adaptors.Config

  @type source :: :npm | :local
  @type name :: String.t()
  @type shape :: :square | :rectangle
  @type ext :: String.t()

  @doc """
  Disk path for an icon. Pure — nothing is checked or created.

  `name` may contain a `/` (scoped npm packages like
  `@openfn/language-foo`); `Path.join/1` preserves the slash so the
  scope becomes a real subdirectory.
  """
  @spec path(source(), name(), shape(), ext()) :: Path.t()
  def path(source, name, shape, ext) do
    Path.join([Config.icon_path(), to_string(source), name, "#{shape}.#{ext}"])
  end

  @doc """
  Whether the icon at `path(source, name, shape, ext)` is on disk with
  bytes hashing to `sha256`.
  """
  @spec cached?(source(), name(), shape(), ext(), binary()) :: boolean()
  def cached?(source, name, shape, ext, sha256) do
    case File.read(path(source, name, shape, ext)) do
      {:ok, bytes} -> :crypto.hash(:sha256, bytes) == sha256
      {:error, _} -> false
    end
  end

  @doc """
  Atomically write `bytes` to `path(source, name, shape, ext)` and
  return the sha256 of the supplied bytes as a 32-byte binary.

  The write is staged in a sibling temp file and then renamed into
  place, so concurrent readers never observe a half-written file.
  """
  @spec write!(source(), name(), shape(), ext(), binary()) ::
          {:ok, binary()}
  def write!(source, name, shape, ext, bytes) when is_binary(bytes) do
    final_path = path(source, name, shape, ext)
    dir = Path.dirname(final_path)
    File.mkdir_p!(dir)

    sha = :crypto.hash(:sha256, bytes)

    temp_path =
      Path.join(dir, ".#{Path.basename(final_path)}.#{random_suffix()}.tmp")

    try do
      File.write!(temp_path, bytes)
      File.rename!(temp_path, final_path)
    rescue
      e ->
        _ = File.rm(temp_path)
        reraise e, __STACKTRACE__
    end

    {:ok, sha}
  end

  @spec random_suffix() :: String.t()
  defp random_suffix do
    8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
