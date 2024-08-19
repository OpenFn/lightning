defmodule Lightning.Storage.Local do
  @behaviour Lightning.Storage.Adapter

  @impl true
  def store(source_path, destination_path) do
    destination_path = Path.join(storage_dir!(), destination_path)
    destination_dir = Path.dirname(destination_path)
    File.mkdir_p!(destination_dir)

    File.cp!(source_path, destination_path)

    {:ok, Path.basename(destination_path)}
  end

  @impl true
  def get(path) do
    File.read(path)
  end

  defp storage_dir!() do
    Application.get_env(:lightning, Lightning.Storage, [])
    |> Keyword.fetch!(:storage_dir)
    |> Path.expand()
  end
end
