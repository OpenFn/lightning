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
  def get_url(path) do
    {:ok, client_email} = Goth.Config.get("client_email")
    {:ok, private_key} = Goth.Config.get("private_key")

    client =
      GcsSignedUrl.Client.load(%{
        "client_email" => client_email,
        "private_key" => private_key
      })

    {:ok,
     GcsSignedUrl.generate_v4(
       client,
       bucket!(),
       path,
       expires: 3600
     )}
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
