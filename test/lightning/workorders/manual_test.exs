defmodule Lightning.WorkOrders.ManualTest do
  use Lightning.DataCase, async: true
  import Lightning.Factories
  alias Lightning.WorkOrders.Manual

  defp manual_attrs(project) do
    [
      project: project,
      job: insert(:job),
      created_by: insert(:user),
      workflow: insert(:workflow, project: project)
    ]
  end

  test "rejects a dataclip_id that belongs to another project" do
    project = insert(:project)
    foreign_dataclip = insert(:dataclip, project: insert(:project))

    changeset =
      Manual.new(%{dataclip_id: foreign_dataclip.id}, manual_attrs(project))

    assert "does not belong to this project" in errors_on(changeset).dataclip_id
  end

  test "accepts a dataclip_id from the run's own project" do
    project = insert(:project)
    dataclip = insert(:dataclip, project: project)

    changeset =
      Manual.new(%{dataclip_id: dataclip.id}, manual_attrs(project))

    refute Map.has_key?(errors_on(changeset), :dataclip_id)
  end

  test "new/2 validates required fields" do
    params = %{}
    changeset = Manual.new(params)

    assert changeset.valid? == false

    for field <- [:project, :job, :created_by, :workflow] do
      assert "can't be blank" in errors_on(changeset)[field]
    end
  end

  test "removes body if dataclip_id is present" do
    params = %{dataclip_id: Ecto.UUID.generate(), body: ~s({"foo": "bar"})}
    changeset = Manual.new(params)

    assert get_change(changeset, :body) == nil
  end

  test "validate_json/2 validates json body" do
    changeset = Manual.new(%{body: "{invalid json"})

    assert "Invalid JSON" in errors_on(changeset).body

    changeset = Manual.new(%{body: "1"})

    assert "Must be an object" in errors_on(changeset).body

    changeset = Manual.new(%{body: ~s({"foo": "bar"})})

    assert changeset |> Ecto.Changeset.get_field(:body) == ~s({"foo": "bar"})
  end

  test "validates presence of either dataclip_id or body" do
    changeset = Manual.new(%{})

    assert "Either a dataclip or a custom body must be present." in errors_on(
             changeset
           ).dataclip_id
  end
end
