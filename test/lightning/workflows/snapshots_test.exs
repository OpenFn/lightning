defmodule Lightning.Workflows.SnapshotsTest do
  use Lightning.DataCase, async: true
  alias Lightning.Workflows

  import Lightning.Factories

  test "testing" do
    workflow = insert(:workflow)

    workflow |> Workflows.update_workflow(%{name: "new name"}) |> IO.inspect()

    meta =
      Carbonite.Query.current_transaction()
      |> Repo.one!()
      |> Map.fetch!(:meta)

    assert meta == %{"type" => "updated"}
  end
end
