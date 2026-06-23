defmodule Lightning.Accounts.AdminSearchParamsTest do
  use ExUnit.Case, async: true

  alias Lightning.Accounts.AdminSearchParams

  describe "new/1" do
    test "normalizes invalid values to safe defaults" do
      loaded? = Code.ensure_loaded?(AdminSearchParams)
      assert loaded?

      params =
        if loaded? do
          AdminSearchParams.new(%{
            "filter" => "  alice  ",
            "sort" => "not_a_column",
            "dir" => "sideways",
            "page" => "-10",
            "page_size" => "1000"
          })
        else
          %{}
        end

      assert Map.take(params, [:filter, :sort, :dir, :page, :page_size]) == %{
               filter: "alice",
               sort: "email",
               dir: "asc",
               page: 1,
               page_size: 100
             }
    end
  end

  describe "to_uri_params/1" do
    test "serializes normalized params for liveview routes" do
      loaded? = Code.ensure_loaded?(AdminSearchParams)
      assert loaded?

      uri_params =
        if loaded? do
          %{
            "filter" => "  bob  ",
            "sort" => "role",
            "dir" => "desc",
            "page" => "3",
            "page_size" => "25"
          }
          |> AdminSearchParams.new()
          |> AdminSearchParams.to_uri_params()
        else
          %{}
        end

      assert uri_params == %{
               "filter" => "bob",
               "sort" => "role",
               "dir" => "desc",
               "page" => "3",
               "page_size" => "25"
             }
    end
  end
end
