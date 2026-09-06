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

  describe "from_map/1" do
    test "rebuilds an identical struct from a JSON round-trip" do
      params =
        SearchParams.new(%{
          "body" => "true",
          "log" => "true",
          "failed" => "true",
          "success" => "true",
          "search_term" => "hello",
          "date_after" => "2023-05-16T12:54"
        })

      round_tripped =
        params
        |> JSON.encode!()
        |> JSON.decode!()
        |> SearchParams.from_map()

      assert {:ok, ^params} = round_tripped
    end

    test "returns an error for stale or malformed args instead of raising" do
      # The export worker relies on this: a bad arg fails the export cleanly
      # rather than crashing the worker or silently broadening the results.
      assert {:error, %Ecto.Changeset{}} =
               SearchParams.from_map(%{"status" => ["gone_status"]})

      assert {:error, %Ecto.Changeset{}} =
               SearchParams.from_map(%{"date_after" => "not-a-date"})

      assert {:error, :invalid_search_params} = SearchParams.from_map(nil)
    end
  end

  describe "to_uri_params/1" do
    test "sets search params values that are not given to default values" do
      assert SearchParams.to_uri_params(%{
               "body" => false,
               "failed" => true,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
             }) == %{
               "id" => true,
               "log" => true,
               "body" => false,
               "failed" => true,
               "wo_date_after" => nil,
               "wo_date_before" => nil,
               "date_after" => nil,
               "date_before" => nil,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4",
               "dataclip_name" => true
             }
    end

    test "includes sort params if given" do
      assert SearchParams.to_uri_params(%{
               "sort_direction" => "desc",
               "sort_by" => "inserted_at",
               "failed" => true,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
             }) == %{
               "id" => true,
               "log" => true,
               "body" => true,
               "failed" => true,
               "wo_date_after" => nil,
               "wo_date_before" => nil,
               "date_after" => nil,
               "date_before" => nil,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4",
               "sort_direction" => "desc",
               "sort_by" => "inserted_at",
               "dataclip_name" => true
             }
    end

    test "converts dates to string" do
      now = DateTime.utc_now()

      assert SearchParams.to_uri_params(%{
               "body" => true,
               "log" => false,
               "id" => false,
               "crashed" => true,
               "date_after" => now,
               "wo_date_before" => now,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4"
             }) == %{
               "body" => true,
               "log" => false,
               "id" => false,
               "crashed" => true,
               "wo_date_after" => nil,
               "wo_date_before" => now |> DateTime.to_string(),
               "date_after" => now |> DateTime.to_string(),
               "date_before" => nil,
               "workflow_id" => "babd29f7-bf15-4a66-af21-51209217ebd4",
               "dataclip_name" => true
             }
    end
  end
end
