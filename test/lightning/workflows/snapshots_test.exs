defmodule Lightning.Workflows.SnapshotsTest do
  use Lightning.DataCase, async: true
  alias Lightning.Workflows

  import Lightning.Factories

  # We're currently creating the triggers in `:ignore` mode, this does not
  # capture changes!
  # However in the near future we may want to explicitly set the mode to `:capture`
  # in the migrations and take stock of tests and functionality that create/update
  # records to ensure they are being captured.

  setup do
    Carbonite.override_mode(Lightning.Repo, to: :capture)
    :ok
  end

  test "creating a new workflow" do
    {:ok, workflow} =
      params_for(:workflow, project: insert(:project))
      |> Workflows.create_workflow()

    workflow_id = workflow.id

    assert Carbonite.Query.current_transaction()
           |> Repo.one!()
           |> Map.fetch!(:meta) == %{"type" => "created"}

    [create_changes] =
      Carbonite.Query.changes(workflow) |> Repo.all()

    assert %Carbonite.Change{
             op: :insert,
             table_name: "workflows",
             table_pk: [^workflow_id]
           } = create_changes

    # assert carbonite_transaction.changes == []
    #   |> IO.inspect()
    #   |> Map.fetch!(:meta)

    # meta |> IO.inspect()

    # workflow |> Workflows.update_workflow(%{name: "new name"})

    # Carbonite.Query.changes(workflow) |> Repo.all() |> IO.inspect()

    # meta =
    #   Carbonite.Query.current_transaction()
    #   |> Repo.one!()
    #   |> IO.inspect()
    #   |> Map.fetch!(:meta)

    # assert meta == %{"type" => "updated"}
  end

  # defp current_transaction_changes() do
  #     Carbonite.Query.current_transaction()
  #     |> Ecto.Query.preload(:changes)
  #     |> Repo.one!()

  # end
end
