defmodule Lightning.Storage.Local do
  @moduledoc """
  A storage backend module for handling local file storage.

  It implements the `Lightning.Storage.Backend` behaviour to manage file storage
  operations on the local file system. This includes storing files from a source
  path to a destination path and generating URLs for accessing stored files.

  ## Responsibilities

  - **Storing Files**: The `store/2` function is responsible for copying files
    from a given source path to a specified destination path on the local file
    system.
  - **Generating URLs**: The `get_url/1` function generates a `file://` URL for
    accessing a stored file locally.
  - **Configuration**: The module relies on application configuration to
    determine the root directory for storage operations.

  ## Example Usage

  ```elixir
  # Store a file
  {:ok, filename} =
    Lightning.Storage.Local.store("/path/to/source", "destination/path")

  # Get the URL for the stored file
  {:ok, url} = Lightning.Storage.Local.get_url("destination/path")
  ```
  """
  @behaviour Lightning.Storage.Backend

  @impl true
  def store(source_path, destination_path) do
    write_path =
      Path.join(storage_dir!(), destination_path)
      |> tap(fn path ->
        path
        |> Path.dirname()
        |> File.mkdir_p!()
      end)

    File.cp!(source_path, write_path)

    {:ok, destination_path}
  end

  @impl true
  def delete(object_path) do
    local_path = Path.join(storage_dir!(), object_path)

    with :ok <- File.rm(local_path), do: {:ok, nil}
  end

  @impl true
  def get_url(path) do
    uri = storage_dir!() |> Path.join(path) |> URI.encode()

    {:ok, "file://" <> uri}
  end

  defp storage_dir! do
    Lightning.Config.storage(:path) |> Path.expand()
  end
end
