defmodule LightningWeb.API.PutBodyTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.Problem
  alias LightningWeb.API.PutBody

  @id "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
  @accepted [:id, :name]

  test "passes a body holding only accepted keys and the path's id" do
    assert PutBody.check(%{"id" => @id, "name" => "n"}, @id, @accepted) ==
             {:ok, []}
  end

  test "passes a body that leaves the id out" do
    assert PutBody.check(%{"name" => "n"}, @id, @accepted) == {:ok, []}
  end

  test "passes a body id written in upper case" do
    assert PutBody.check(%{"id" => String.upcase(@id)}, @id, @accepted) ==
             {:ok, []}
  end

  test "answers 400 malformed for a body that is not a JSON object" do
    assert PutBody.check(%{"_json" => [1, 2]}, @id, @accepted) ==
             {:error, Problem.new(:malformed)}
  end

  test "gives one unknown_key entry per key the route does not accept, and a mismatch for another id" do
    body = %{
      "id" => "0b9e0a5e-7d55-4d8e-8f7e-4a0b1c2d3e4f",
      "name" => "n",
      "colour" => "red",
      "a/b" => 1
    }

    assert PutBody.check(body, @id, @accepted) ==
             {:ok,
              [
                %{
                  pointer: "#/a~1b",
                  code: :unknown_key,
                  detail: "is not accepted"
                },
                %{
                  pointer: "#/colour",
                  code: :unknown_key,
                  detail: "is not accepted"
                },
                %{
                  pointer: "#/id",
                  code: :mismatch,
                  detail: "does not match the id in the path"
                }
              ]}
  end

  test "gives a mismatch for a body id that is not a UUID" do
    assert PutBody.check(%{"id" => 42}, @id, @accepted) ==
             {:ok,
              [
                %{
                  pointer: "#/id",
                  code: :mismatch,
                  detail: "does not match the id in the path"
                }
              ]}
  end

  test "gives a mismatch for a 16-byte body id whose raw bytes are the path's id" do
    raw = "aaaaaaaaaaaaaaaa"
    path_id = Ecto.UUID.cast!(raw)

    assert PutBody.check(%{"id" => raw}, path_id, @accepted) ==
             {:ok,
              [
                %{
                  pointer: "#/id",
                  code: :mismatch,
                  detail: "does not match the id in the path"
                }
              ]}
  end

  describe "path_id/1" do
    test "takes a UUID written out, in any case" do
      assert PutBody.path_id(String.upcase(@id)) == {:ok, @id}
    end

    test "answers not_found for anything else, a 16-byte string included" do
      for id <- ["not-a-uuid", "aaaaaaaaaaaaaaaa", ""] do
        assert PutBody.path_id(id) == {:error, :not_found}, inspect(id)
      end
    end
  end

  describe "id_taken?/1" do
    defp refused(field, opts) do
      {%{}, %{id: :binary_id, name: :string}}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(field, "has already been taken", opts)
    end

    test "is true only for the id's unique constraint" do
      assert PutBody.id_taken?(refused(:id, constraint: :unique))
      refute PutBody.id_taken?(refused(:name, constraint: :unique))
      refute PutBody.id_taken?(refused(:id, validation: :required))
    end
  end
end
