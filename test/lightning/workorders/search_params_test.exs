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
        "search_term" => "hello",
        "success" => "true",
        "timeout" => "true",
        "wo_date_after" => "2023-05-09T12:54",
        "wo_date_before" => "2023-05-16T12:54",
        "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
      }

      assert {:ok,
              %SearchParams{
                date_after: ~U[2023-05-16 12:54:00Z],
                date_before: ~U[2023-05-23 12:55:00Z],
                search_fields: [:body, :log],
                search_term: "hello",
                status: [
                  :crash,
                  :failure,
                  :pending,
                  :success,
                  :timeout
                ],
                wo_date_after: ~U[2023-05-09 12:54:00Z],
                wo_date_before: ~U[2023-05-16 12:54:00Z],
                workflow_id: "babd29f7-bf15-4a66-af21-51209217ebd4"
              }} == SearchParams.new(params)
    end
  end
end
