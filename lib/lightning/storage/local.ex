defmodule Lightning.Storage.Local do
  @behaviour Lightning.Storage.Backend

  @impl true
  def store(source_path, destination_path) do
    destination_path = Path.join(storage_dir!(), destination_path)
    destination_dir = Path.dirname(destination_path)
    File.mkdir_p!(destination_dir)

    File.cp!(source_path, destination_path)

    {:ok, Path.basename(destination_path)}
  end

  @impl true
  def get_url(path) do
    uri = storage_dir!() |> Path.join(path) |> URI.encode()

    {:ok, "file://" <> uri}
  end

  defp storage_dir!() do
    Application.get_env(:lightning, Lightning.Storage, [])
    |> Keyword.fetch!(:storage_dir)
    |> Path.expand()
  end
end
