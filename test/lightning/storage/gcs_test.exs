defmodule Lightning.Storage.GCSTest do
  use ExUnit.Case, async: true

  import Mox

  alias Lightning.Storage.GCS

  @bucket "lightning-test"
  @storage_path "uploads/security"

  setup :verify_on_exit!

  setup do
    stub(Lightning.Storage.GCS.MockTokenSource, :fetch, fn ->
      {:ok, %{token: "a-bearer-token"}}
    end)

    stub(Lightning.MockConfig, :storage, fn
      :path -> @storage_path
      :bucket -> @bucket
    end)

    :ok
  end

  defp source_file(contents) do
    path =
      Path.join(
        System.tmp_dir!(),
        "gcs-test-#{System.unique_integer([:positive])}"
      )

    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    path
  end

  defp expect_request(response) do
    test_pid = self()

    expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
      send(test_pid, {:request, env})
      response
    end)
  end

  describe "store/2" do
    setup do
      %{source: source_file("an export")}
    end

    test "uploads with uploadType=media and the storage path prefix", %{
      source: source
    } do
      expect_request({:ok, %Tesla.Env{status: 200, body: "{}"}})

      assert {:ok, %Tesla.Env{status: 200}} =
               GCS.store(source, "exports/project/file.zip")

      assert_received {:request, env}

      assert env.method == :post

      assert env.url ==
               "https://storage.googleapis.com/upload/storage/v1/b/#{@bucket}/o"

      assert env.query == [
               uploadType: "media",
               name: "#{@storage_path}/exports/project/file.zip"
             ]

      assert {"content-type", "application/octet-stream"} in env.headers
      assert {"authorization", "Bearer a-bearer-token"} in env.headers
    end

    test "sends the body as a chunkable Stream, not a File.Stream", %{
      source: source
    } do
      expect_request({:ok, %Tesla.Env{status: 200, body: "{}"}})

      GCS.store(source, "exports/project/file.zip")

      assert_received {:request, env}

      # Tesla's adapters match on %Stream{} to send a chunked body; a bare
      # %File.Stream{} falls through and the request fails.
      assert %Stream{} = env.body
      assert Enum.join(env.body) == "an export"
    end

    test "returns an error tuple for a non-2xx response", %{source: source} do
      expect_request({:ok, %Tesla.Env{status: 403, body: "no access"}})

      assert {:error, %Tesla.Env{status: 403, body: "no access"}} =
               GCS.store(source, "exports/project/file.zip")
    end

    test "returns an error tuple when the request never completes", %{
      source: source
    } do
      expect_request({:error, :econnrefused})

      assert {:error, :econnrefused} =
               GCS.store(source, "exports/project/file.zip")
    end
  end

  describe "delete/1" do
    test "deletes the prefixed object path, escaped as one segment" do
      expect_request({:ok, %Tesla.Env{status: 204, body: ""}})

      assert {:ok, %Tesla.Env{status: 204}} =
               GCS.delete("exports/project/file.zip")

      assert_received {:request, env}

      assert env.method == :delete

      assert env.url ==
               "https://storage.googleapis.com/storage/v1/b/#{@bucket}/o/" <>
                 "uploads%2Fsecurity%2Fexports%2Fproject%2Ffile.zip"

      assert {"authorization", "Bearer a-bearer-token"} in env.headers
    end

    test "surfaces a 404 so callers can treat the object as already gone" do
      expect_request({:ok, %Tesla.Env{status: 404, body: "Not Found"}})

      assert {:error, %Tesla.Env{status: 404}} =
               GCS.delete("exports/project/file.zip")
    end
  end

  describe "bucket configuration" do
    test "raises a pointed error when no bucket is configured" do
      stub(Lightning.MockConfig, :storage, fn
        :path -> @storage_path
        :bucket -> nil
      end)

      assert_raise RuntimeError, ~r/GCS_BUCKET/, fn ->
        GCS.delete("exports/project/file.zip")
      end
    end
  end
end
