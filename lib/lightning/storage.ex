defmodule Lightning.Storage do
  @behaviour Lightning.Storage.Adapter

  @impl true
  def store(source_path, destination_path) do
    adapter().store(source_path, destination_path)
  end

  @impl true
  def get(path) do
    adapter().get(path)
  end

  defp adapter() do
    Lightning.Config.storage_backend()
  end
end
