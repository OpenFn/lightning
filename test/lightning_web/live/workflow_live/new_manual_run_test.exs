defmodule LightningWeb.WorkflowLive.NewManualRunTest do
  use LightningWeb.ConnCase

  alias LightningWeb.WorkflowLive.NewManualRun

  test "get_dataclips_filters/1" do
    assert {:ok, %{}} = NewManualRun.get_dataclips_filters("query=+")

    assert {:ok, %{before: ~N[2025-05-14 14:35:00]}} =
             NewManualRun.get_dataclips_filters(
               "query=+&before=2025-05-14T14%3A35"
             )

    assert {:ok,
            %{before: ~N[2025-05-14 14:35:00], after: ~N[2025-05-14 14:55:00]}} =
             NewManualRun.get_dataclips_filters(
               "query=+&before=2025-05-14T14%3A35&after=2025-05-14T14%3A55"
             )

    assert {:ok, %{id_prefix: "1f"}} =
             NewManualRun.get_dataclips_filters("query=1f")

    uuid = "3a80bd03-6f0b-4146-8b23-e5ca9f3176bb"

    assert {:ok, %{id: ^uuid}} =
             NewManualRun.get_dataclips_filters("query=#{uuid}")

    assert {:error, changeset} =
             NewManualRun.get_dataclips_filters(
               "query=1z&before=2025-05-14T14%3A35"
             ),
           "Partial uuids that are not base 16 should be rejected"

    assert {:query, {"is invalid", []}} in changeset.errors

    assert {:error, changeset} =
             NewManualRun.get_dataclips_filters("query=#{uuid}z"),
           "Invalid uuids should be rejected"

    assert {:query, {"is invalid", []}} in changeset.errors

    for type <- Lightning.Invocation.Dataclip.source_types() do
      assert {:ok, %{type: ^type}} =
               NewManualRun.get_dataclips_filters("query=+&type=#{type}"),
             "should allow a type of #{type}"
    end

    assert {:error, changeset} =
             NewManualRun.get_dataclips_filters("query=+&type=invalid_type")

    assert changeset.errors |> Enum.any?(&match?({:type, {"is invalid", _}}, &1))
  end
end
