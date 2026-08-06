defmodule Lightning.Storage.GCS do
  @moduledoc """
  A storage backend module for handling file storage in Google Cloud Storage (GCS).

  It implements the `Lightning.Storage.Backend` behaviour to manage file storage operations in Google Cloud Storage. This includes storing files to GCS buckets and generating signed URLs for secure access to the stored files.

  Requests are made against the GCS JSON API directly, with a bearer token from
  `Lightning.Storage.GCS.TokenSource`. All object paths are prefixed with the
  configured `STORAGE_PATH` before they reach the API.

  ## Responsibilities

  - **Storing Files**: The `store/2` function uploads files from a local source path to a specified destination path within a GCS bucket.
  - **Deleting Files**: The `delete/1` function removes an object from the bucket.
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

  alias Lightning.Storage.GCS.TokenSource

  @host "https://storage.googleapis.com"

  @impl true
  def store(source_path, destination_path) do
    {:ok, destination_path} = prefix_storage_path(destination_path)

    conn()
    |> Tesla.post(
      "#{@host}/upload/storage/v1/b/#{encode(bucket!())}/o",
      stream_file(source_path),
      query: [uploadType: "media", name: destination_path],
      headers: [{"content-type", "application/octet-stream"}]
    )
    |> handle_response()
  end

  @impl true
  def delete(object_path) do
    {:ok, object_path} = prefix_storage_path(object_path)

    conn()
    |> Tesla.delete(
      "#{@host}/storage/v1/b/#{encode(bucket!())}/o/#{encode(object_path)}"
    )
    |> handle_response()
  end

  @impl true
  def get_url(path) do
    client =
      Lightning.Config.google(:credentials)
      |> Map.take(["client_email", "private_key"])
      |> GcsSignedUrl.Client.load()

    {:ok, path} = prefix_storage_path(path)

    {:ok,
     GcsSignedUrl.generate_v4(
       client,
       bucket!(),
       path,
       expires: 3600
     )}
  end

  defp handle_response({:ok, %Tesla.Env{status: status} = env})
       when status in 200..299,
       do: {:ok, env}

  defp handle_response({:ok, %Tesla.Env{} = env}), do: {:error, env}
  defp handle_response({:error, reason}), do: {:error, reason}

  # Wrapped in Stream.map/2 so it is a %Stream{}, which is what the Tesla
  # adapters match on to send a chunked body. A bare %File.Stream{} isn't.
  defp stream_file(source_path) do
    source_path
    |> File.stream!(64 * 1024)
    |> Stream.map(& &1)
  end

  # Object paths are a single path segment in the JSON API, so "/" has to be
  # escaped to %2F rather than left as a separator.
  defp encode(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  defp bucket! do
    Lightning.Config.storage(:bucket) ||
      raise "No GCS bucket configured. Set GCS_BUCKET when STORAGE_BACKEND=gcs."
  end

  defp conn do
    {:ok, token} = TokenSource.fetch()

    Tesla.client([
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token.token}"}]}
    ])
  end

  defp prefix_storage_path(destination_path) do
    Path.safe_relative(
      Path.join(Lightning.Config.storage(:path), destination_path)
    )
  end
end
