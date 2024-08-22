defmodule Lightning.Storage.GCS do
  @moduledoc """
  A storage backend module for handling file storage in Google Cloud Storage (GCS).

  It implements the `Lightning.Storage.Backend` behaviour to manage file storage operations in Google Cloud Storage. This includes storing files to GCS buckets and generating signed URLs for secure access to the stored files.

  ## Responsibilities

  - **Storing Files**: The `store/2` function uploads files from a local source path to a specified destination path within a GCS bucket.
  - **Generating Signed URLs**: The `get_url/1` function generates a signed URL for accessing a file stored in GCS. This signed URL is valid for a limited time (default 1 hour).
  - **Configuration**: The module relies on application configuration to determine the GCS bucket and Google API connection settings.

  ## Example Usage

  ```elixir
  # Store a file in GCS
  Lightning.Storage.GCS.store("/path/to/source", "destination/path")

  # Get a signed URL for the stored file
  {:ok, url} = Lightning.Storage.GCS.get_url("destination/path")
  ```
  """
  @behaviour Lightning.Storage.Backend

  alias GoogleApi.Storage.V1.Api.Objects
  alias GoogleApi.Storage.V1.Model.Object

  @impl true
  def store(source_path, destination_path) do
    object = %Object{name: destination_path, bucket: bucket!()}

    Objects.storage_objects_insert_simple(
      conn(),
      bucket!(),
      "multipart",
      object,
      source_path
    )
  end

  @impl true
  def get_url(path) do
    client =
      Lightning.Config.google(:credentials)
      |> Map.take(["client_email", "private_key"])
      |> GcsSignedUrl.Client.load()

    {:ok,
     GcsSignedUrl.generate_v4(
       client,
       bucket!(),
       path,
       expires: 3600
     )}
  end

  defp bucket! do
    Application.get_env(:lightning, Lightning.Storage, [])
    |> Keyword.fetch!(:bucket)
  end

  defp conn do
    {:ok, token} = Goth.fetch(Lightning.Goth)
    GoogleApi.Storage.V1.Connection.new(token.token)
  end
end
