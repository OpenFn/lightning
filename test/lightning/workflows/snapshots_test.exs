defmodule Lightning.Workflows.SnapshotsTest do
  use Lightning.DataCase, async: false
  alias Lightning.Workflows

  import Lightning.Factories

  # We're currently creating the triggers in `:ignore` mode, this does not
  # capture changes!
  # However in the near future we may want to explicitly set the mode to `:capture`
  # in the migrations and take stock of tests and functionality that create/update
  # records to ensure they are being captured.

  setup do
    enable_transaction_capture()
    :ok
  end

  test "creating a new workflow" do
    {:ok, workflow} =
      params_for(:workflow, project: insert(:project))
      |> Workflows.create_workflow()

    workflow_id = workflow.id

    assert Carbonite.Query.current_transaction(
             carbonite_prefix: Lightning.Config.audit_schema()
           )
           |> Repo.one!()
           |> Map.fetch!(:meta) == %{"type" => "created"}

    [create_changes] =
      Carbonite.Query.changes(workflow,
        carbonite_prefix: Lightning.Config.audit_schema()
      )
      |> Repo.all()

    assert %Carbonite.Change{
             op: :insert,
             table_name: "workflows",
             table_pk: [^workflow_id]
           } = create_changes
  end

  test "processing changes" do
    {:ok, workflow} =
      params_for(:workflow, project: insert(:project))
      |> Workflows.create_workflow()

    workflow
    |> Workflows.update_workflow(%{name: "new name", jobs: [params_for(:job)]})

    Carbonite.Query.transactions(
      carbonite_prefix: Lightning.Config.audit_schema()
    )
    |> Repo.all()
  end
end
