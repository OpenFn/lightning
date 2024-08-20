defmodule Lightning.StorageTest do
  use ExUnit.Case, async: true

  alias Lightning.Storage

  import Mox

  setup_all do
    Mox.defmock(MockStorageBackend, for: Lightning.Storage.Backend)

    :ok
  end

  setup :verify_on_exit!

  test "should call store on the current backend" do
    Lightning.MockConfig
    |> expect(:storage_backend, fn -> MockStorageBackend end)

    MockStorageBackend |> expect(:store, fn _, _ -> {:ok, "path"} end)

    assert Storage.store("source", "destination") == {:ok, "path"}
  end

  test "should call get_url on the current backend" do
    Lightning.MockConfig
    |> expect(:storage_backend, fn -> MockStorageBackend end)

    MockStorageBackend |> expect(:get_url, fn _ -> {:ok, "path"} end)

    assert Storage.get_url("some_path") == {:ok, "path"}
  end
end
