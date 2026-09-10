defmodule AdaptorCache.Scenario do
  @moduledoc """
  `scenario save`/`restore` — named, repeatable cache states, checked out of
  git (see `.gitignore` in this directory).
  """

  alias AdaptorCache.Cache

  def scenarios_root, do: Path.expand("../scenarios", __DIR__)

  def save(name) do
    with {:ok, dir} <- scenario_dir(name) do
      File.rm_rf!(dir)
      File.mkdir_p!(dir)

      Enum.each(Cache.data_dirs(), fn data_dir ->
        src = Path.join(Cache.root(), data_dir)
        if File.dir?(src), do: File.cp_r!(src, Path.join(dir, data_dir))
      end)

      :ok
    end
  end

  def restore(name) do
    with {:ok, dir} <- scenario_dir(name),
         {:ok, dir} <- require_dir(dir, name) do
      Cache.purge()

      Enum.each(Cache.data_dirs(), fn data_dir ->
        src = Path.join(dir, data_dir)
        if File.dir?(src), do: File.cp_r!(src, Path.join(Cache.root(), data_dir))
      end)

      :ok
    end
  end

  defp require_dir(dir, name) do
    if File.dir?(dir),
      do: {:ok, dir},
      else:
        {:error, "no scenario named #{inspect(name)} under #{scenarios_root()}"}
  end

  # A scenario name becomes a raw directory segment — contain it under
  # scenarios_root() the same way Cache.key_path contains a request path,
  # so `scenario save ../../..` can't walk out of this directory.
  defp scenario_dir(name) do
    root = scenarios_root()
    dir = Path.expand(Path.join(root, name))

    if String.starts_with?(dir, root <> "/"),
      do: {:ok, dir},
      else: {:error, "invalid scenario name #{inspect(name)}"}
  end
end
