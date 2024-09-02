defmodule Lightning.Storage do
  @moduledoc """
  The external storage module.

  This module is responsible for storing and retrieving files from the
  configured storage backend.
  """
  @behaviour Lightning.Storage.Backend

  @impl true
  def store(source_path, destination_path) do
    adapter().store(source_path, destination_path)
  end

  @impl true
  def get_url(path) do
    adapter().get_url(path)
  end

  defp adapter do
    Lightning.Config.storage(:backend)
  end
end
