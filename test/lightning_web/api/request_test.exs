defmodule LightningWeb.API.RequestTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request

  @id "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
  @accepted [:id, :name]

  @mismatch %{
    pointer: "#/id",
    code: :mismatch,
    detail: "does not match the id in the path"
  }

  test "passes a body holding only accepted keys, with the path's id in either case or left out" do
    for body <- [
          %{"id" => @id, "name" => "n"},
          %{"name" => "n"},
          %{"id" => String.upcase(@id)}
        ],
        path_id <- [@id, String.upcase(@id)] do
      assert Request.check(body, path_id, @accepted) == {:ok, []},
             inspect({body, path_id})
    end
  end

  test "answers 400 malformed for a body that is not a JSON object" do
    assert Request.check(%{"_json" => [1, 2]}, @id, @accepted) ==
             {:error, Problem.new(:malformed)}
  end

  test "gives one unknown_key entry per key the route does not accept, in key order" do
    body = %{"id" => @id, "name" => "n", "colour" => "red", "a/b" => 1}

    assert Request.check(body, @id, @accepted) ==
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
                }
              ]}
  end

  test "gives a mismatch for a body id that is another UUID, is not a UUID, or is a 16-byte string whose raw bytes are the path's id" do
    raw = "aaaaaaaaaaaaaaaa"

    for {body_id, path_id} <- [
          {"0b9e0a5e-7d55-4d8e-8f7e-4a0b1c2d3e4f", @id},
          {42, @id},
          {raw, Ecto.UUID.cast!(raw)}
        ] do
      assert Request.check(%{"id" => body_id}, path_id, @accepted) ==
               {:ok, [@mismatch]},
             inspect(body_id)
    end
  end

  test "gives unknown keys and a mismatch together" do
    body = %{"id" => "0b9e0a5e-7d55-4d8e-8f7e-4a0b1c2d3e4f", "colour" => "red"}

    assert Request.check(body, @id, @accepted) ==
             {:ok,
              [
                %{
                  pointer: "#/colour",
                  code: :unknown_key,
                  detail: "is not accepted"
                },
                @mismatch
              ]}
  end

  describe "validate_matches_path/4" do
    defp matched(body, path_id) do
      {%{}, %{project_id: :binary_id}}
      |> Ecto.Changeset.change()
      |> Request.validate_matches_path(body, :project_id, path_id)
    end

    test "adds a mismatch error on the field when the body names another id there" do
      changeset = matched(%{"project_id" => Ecto.UUID.generate()}, @id)

      assert changeset.errors == [
               project_id: {"does not match the id in the path", code: :mismatch}
             ]
    end

    test "leaves the changeset alone when the body names the path's id there, in any case, or names none" do
      for body <- [
            %{"project_id" => @id},
            %{"project_id" => String.upcase(@id)},
            %{}
          ] do
        assert matched(body, @id).errors == [], inspect(body)
      end
    end
  end

  describe "id/1" do
    test "takes a UUID written out, in any case" do
      assert Request.id({{:path, "id"}, String.upcase(@id)}) == {:ok, @id}
    end

    test "answers invalid_id naming where the request sent it for anything else, a 16-byte string included" do
      for id <- ["not-a-uuid", "aaaaaaaaaaaaaaaa", "", nil],
          location <- [{:path, "id"}, {:parameter, "project_id"}, [:id]] do
        assert Request.id({location, id}) == {:error, {:invalid_id, location}},
               inspect({location, id})
      end
    end
  end

  describe "param/2" do
    test "reads the parameter from the path, then the query, then the body" do
      conn = %Plug.Conn{
        path_params: %{"id" => "path"},
        query_params: %{"id" => "query", "project_id" => "query"},
        body_params: %{"id" => "body", "project_id" => "body", "name" => "n"}
      }

      assert Enum.map(["id", "project_id", "name"], &Request.param(conn, &1)) ==
               [
                 {{:path, "id"}, "path"},
                 {{:parameter, "project_id"}, "query"},
                 {["name"], "n"}
               ]
    end
  end

  describe "id_taken?/1" do
    defp refused(field, opts) do
      {%{}, %{id: :binary_id, name: :string}}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(field, "has already been taken", opts)
    end

    test "is true only for the id's unique constraint" do
      assert Request.id_taken?(refused(:id, constraint: :unique))
      refute Request.id_taken?(refused(:name, constraint: :unique))
      refute Request.id_taken?(refused(:id, validation: :required))
    end
  end
end
