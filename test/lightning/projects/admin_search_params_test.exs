defmodule Lightning.Projects.AdminSearchParamsTest do
  use ExUnit.Case, async: true

  alias Lightning.Projects.AdminSearchParams

  describe "new/1" do
    test "normalizes invalid values to safe defaults" do
      params =
        AdminSearchParams.new(%{
          "search_term" => "  alpha  ",
          "sort_by" => "drop table projects",
          "sort_direction" => "sideways",
          "page" => "0",
          "page_size" => "1000"
        })

      assert Map.take(params, [
               :search_term,
               :sort_by,
               :sort_direction,
               :page,
               :page_size
             ]) == %{
               search_term: "alpha",
               sort_by: "name",
               sort_direction: "asc",
               page: 1,
               page_size: 100
             }
    end
  end

  describe "to_uri_params/1" do
    test "serializes normalized params for liveview routes" do
      uri_params =
        %{
          "search_term" => "  jane  ",
          "sort_by" => "owner",
          "sort_direction" => "desc",
          "page" => "4",
          "page_size" => "25"
        }
        |> AdminSearchParams.new()
        |> AdminSearchParams.to_uri_params()

      assert uri_params == %{
               "search_term" => "jane",
               "sort_by" => "owner",
               "sort_direction" => "desc",
               "page" => "4",
               "page_size" => "25"
             }
    end
  end
end
