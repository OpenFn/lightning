defmodule Lightning.Workorders.SearchParamsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workorders.SearchParams

  describe "new/1" do
    test "returns a struct with the given params" do
      params = %{
        "body" => "true",
        "crash" => "true",
        "date_after" => "2023-05-16T12:54",
        "date_before" => "2023-05-23T12:55",
        "failure" => "true",
        "log" => "true",
        "pending" => "true",
        "search_term" => "",
        "success" => "true",
        "timeout" => "true",
        "wo_date_after" => "2023-05-09T12:54",
        "wo_date_before" => "2023-05-16T12:54",
        "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
      }

      assert %SearchParams{} = SearchParams.new(params) |> IO.inspect()
    end
  end
end
