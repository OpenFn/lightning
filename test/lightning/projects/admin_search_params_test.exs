defmodule Lightning.Projects.AdminSearchParamsTest do
  use ExUnit.Case, async: true

  alias Lightning.Projects.AdminSearchParams

  describe "new/1" do
    test "normalizes invalid values to safe defaults" do
      loaded? = Code.ensure_loaded?(AdminSearchParams)
      assert loaded?

      params =
        if loaded? do
          AdminSearchParams.new(%{
            "filter" => "  alpha  ",
            "sort" => "drop table projects",
            "dir" => "sideways",
            "page" => "0",
            "page_size" => "1000"
          })
        else
          %{}
        end

      assert Map.take(params, [:filter, :sort, :dir, :page, :page_size]) == %{
               filter: "alpha",
               sort: "name",
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
            "filter" => "  jane  ",
            "sort" => "owner",
            "dir" => "desc",
            "page" => "4",
            "page_size" => "25"
          }
          |> AdminSearchParams.new()
          |> AdminSearchParams.to_uri_params()
        else
          %{}
        end

      assert uri_params == %{
               "filter" => "jane",
               "sort" => "owner",
               "dir" => "desc",
               "page" => "4",
               "page_size" => "25"
             }
    end
  end
end
