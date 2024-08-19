defmodule Lightning.Storage.GCS do
  @behaviour Lightning.Storage.Adapter

  alias GoogleApi.Storage.V1.Model.Object
  alias GoogleApi.Storage.V1.Api.Objects

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
  def get(path) do
    conn = conn()

    with {:ok, object} <- Objects.storage_objects_get(conn, bucket!(), path),
         {:ok, %Tesla.Env{body: body}} <- Tesla.get(conn, object.mediaLink) do
      {:ok, body}
    end
  end

  defp bucket!() do
    Application.get_env(:lightning, Lightning.Storage, [])
    |> Keyword.fetch!(:bucket)
  end

  defp conn() do
    {:ok, token} = Goth.fetch(Lightning.Goth)
    GoogleApi.Storage.V1.Connection.new(token.token)
  end
end
