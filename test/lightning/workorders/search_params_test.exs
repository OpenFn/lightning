defmodule Lightning.WorkOrders.SearchParamsTest do
  use Lightning.DataCase, async: true

  alias Lightning.WorkOrders.SearchParams

  describe "new/1" do
    test "returns a struct with the given params" do
      params = %{
        "body" => "true",
        "date_after" => "2023-05-16T12:54",
        "date_before" => "2023-05-23T12:55",
        "success" => "true",
        "failed" => "true",
        "pending" => "true",
        "killed" => "true",
        "crashed" => "true",
        "running" => "true",
        "log" => "true",
        "search_term" => "hello",
        "wo_date_after" => "2023-05-09T12:54",
        "wo_date_before" => "2023-05-16T12:54",
        "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
      }

      assert %SearchParams{
               date_after: ~U[2023-05-16 12:54:00.000000Z],
               date_before: ~U[2023-05-23 12:55:00.000000Z],
               search_fields: [:body, :log],
               search_term: "hello",
               status: [
                 :crashed,
                 :failed,
                 :killed,
                 :pending,
                 :running,
                 :success
               ],
               wo_date_after: ~U[2023-05-09 12:54:00.000000Z],
               wo_date_before: ~U[2023-05-16 12:54:00.000000Z],
               workflow_id: "babd29f7-bf15-4a66-af21-51209217ebd4"
             } == SearchParams.new(params)
    end
  end

  describe "to_uri_params/1" do
    test "sets search params values that are not given to default values" do
      assert SearchParams.to_uri_params(%{
               "body" => false,
               "failed" => false,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
             }) == %{
               "log" => true,
               "body" => false,
               "pending" => true,
               "running" => true,
               "success" => true,
               "failed" => false,
               "crashed" => true,
               "killed" => true,
               "cancelled" => true,
               "exception" => true,
               "lost" => true,
               "wo_date_after" => nil,
               "wo_date_before" => nil,
               "date_after" => nil,
               "date_before" => nil,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
             }
    end

    test "converts dates to string" do
      now = DateTime.utc_now()

      assert SearchParams.to_uri_params(%{
               "log" => false,
               "crashed" => true,
               "failed" => false,
               "date_after" => now,
               "wo_date_before" => now,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
             }) == %{
               "log" => false,
               "body" => true,
               "pending" => true,
               "running" => true,
               "success" => true,
               "failed" => false,
               "crashed" => true,
               "killed" => true,
               "cancelled" => true,
               "exception" => true,
               "lost" => true,
               "wo_date_after" => nil,
               "wo_date_before" => now |> DateTime.to_string(),
               "date_after" => now |> DateTime.to_string(),
               "date_before" => nil,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
             }
    end
  end
end
