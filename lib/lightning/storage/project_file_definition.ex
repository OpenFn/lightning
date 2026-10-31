defmodule Lightning.Storage.ProjectFileDefinition do
  @moduledoc """
    This module provides functionality for managing the storage and retrieval of project files.

    It handles operations related to storing project files, generating URLs for accessing these files, and constructing storage paths for exported files. It serves as an abstraction layer over the underlying storage mechanism provided by the `Lightning.Storage` module.

    ## Functions

    - `store/2`: Stores a file from a given source path into the storage system based on the file's path.
    - `get_url/1`: Retrieves the URL for accessing a stored file.
    - `delete/1`: Removes a stored file from the storage system.
    - `storage_path_for_exports/2`: Constructs a storage path for exported files, defaulting to a `.zip` extension.

    ## Example Usage

    ```elixir
    # Store a file
    Lightning.Storage.ProjectFileDefinition.store("/path/to/source", project_file)

    # Get a URL for the stored file
    url = Lightning.Storage.ProjectFileDefinition.get_url(project_file)

    # Delete a stored file
    :ok = Lightning.Storage.ProjectFileDefinition.delete(project_file)

    # Get the storage path for an exported file
    path = Lightning.Storage.ProjectFileDefinition.storage_path_for_exports(project_file)
    ```
  """

  alias Lightning.Projects.File, as: ProjectFile
  alias Lightning.Storage

  def store(source_path, %ProjectFile{} = file) do
    Storage.store(source_path, file.path)
  end

  def get_url(%ProjectFile{} = file) do
    Storage.get_url(file.path)
  end

  @doc """
  Deletes a file's object from storage.

  Returns `:ok` once nothing is stored for the file, which includes the cases
  where there never was anything: a file with no path (a failed export never
  wrote one), and a path the backend doesn't recognise. Backends spell that last
  one differently — GCS answers `404`, the local backend `:enoent` — and callers
  shouldn't have to know which backend they're on.

  Anything else means the object may still be there, and comes back as
  `{:error, reason}`.
  """
  @spec delete(ProjectFile.t()) :: :ok | {:error, term()}
  def delete(%ProjectFile{path: nil}), do: :ok

  def delete(%ProjectFile{path: path}) do
    case Storage.delete(path) do
      {:ok, _res} -> :ok
      {:error, %{status: 404}} -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def storage_path_for_exports(%ProjectFile{} = file, ext \\ ".zip") do
    Path.join(["exports", file.project_id, "#{file.id}#{ext}"])
  end
end
