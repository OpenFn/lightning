defmodule Lightning.Channels.SearchParamsTest do
  use ExUnit.Case, async: true

  alias Lightning.Channels.SearchParams

  describe "new/1" do
    test "a well-formed channel_id is kept" do
      id = Ecto.UUID.generate()

      assert %SearchParams{channel_id: ^id} =
               SearchParams.new(%{"channel_id" => id})
    end

    test "a malformed channel_id coerces to an empty struct" do
      assert %SearchParams{channel_id: nil} =
               SearchParams.new(%{"channel_id" => "__ID_WF_Foo_____"})
    end

    test "a missing channel_id yields an empty struct" do
      assert %SearchParams{channel_id: nil} = SearchParams.new(%{})
    end
  end

  describe "changeset/1" do
    test "a malformed channel_id is a changeset error" do
      cs = SearchParams.changeset(%{"channel_id" => "__ID_WF_Foo_____"})
      refute cs.valid?
      assert {"is not a valid UUID", _} = cs.errors[:channel_id]
    end
  end
end
