defmodule Lightning.Storage do
  @behaviour Lightning.Storage.Adapter

  @impl true
  def store(source_path, destination_path) do
    adapter().store(source_path, destination_path)
  end

  @impl true
  def get_url(path) do
    adapter().get_url(path)
  end

  defp adapter() do
    Lightning.Config.storage_backend()
  end
end
