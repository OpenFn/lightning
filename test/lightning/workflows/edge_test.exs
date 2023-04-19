defmodule Lightning.Workflows.EdgeTest do
  use Lightning.DataCase

  alias Lightning.Workflows.Edge

  describe "changeset/2" do
    test "valid changeset" do
      changeset = Edge.changeset(%Edge{}, %{workflow_id: Ecto.UUID.generate()})
      assert changeset.valid?
    end
  end
end
