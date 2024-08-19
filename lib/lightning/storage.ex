defmodule Lightning.Storage do
  def store(source_path, destination_path) do
    adapter().store(source_path, destination_path)
  end

  def get(path) do
    adapter().get(path)
  end

  defp adapter() do
    Application.get_env(:lightning, Lightning.Storage, [])
    |> Keyword.fetch!(:adapter)
  end
end
