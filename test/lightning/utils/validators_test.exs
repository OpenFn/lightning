defmodule Lightning.ValidatorsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  import Lightning.Validators, only: [validate_uuid: 2, valid_uuid?: 1]

  defmodule Holder do
    use Ecto.Schema

    # Use :binary_id (not Ecto.UUID) to mirror the real schema fields the
    # validator guards (Job.id, Trigger.id, cron_cursor_job_id). Unlike
    # Ecto.UUID, :binary_id `cast/3` does NOT re-format a 16-byte binary into a
    # canonical hex UUID — it passes the raw string straight through, which is
    # exactly the value that later fails at `Ecto.UUID.dump/1` on insert.
    @primary_key false
    embedded_schema do
      field :ref_id, :binary_id
    end
  end

  defp changeset(value) do
    %Holder{}
    |> cast(%{ref_id: value}, [:ref_id])
    |> validate_uuid(:ref_id)
  end

  describe "validate_uuid/2" do
    test "rejects a 16-byte non-hex string (the dump/cast asymmetry)" do
      cs = changeset("__ID_JOB_Fetch__")
      refute cs.valid?
      assert cs.errors[:ref_id] == {"is not a valid UUID", []}
    end

    test "accepts a canonical UUID" do
      cs = changeset(Ecto.UUID.generate())
      assert cs.valid?
      assert cs.errors[:ref_id] == nil
    end

    test "passes through when the field is nil / absent" do
      assert changeset(nil).valid?

      assert %Holder{}
             |> cast(%{}, [:ref_id])
             |> validate_uuid(:ref_id)
             |> Map.fetch!(:valid?)
    end
  end

  describe "valid_uuid?/1" do
    test "accepts canonical UUIDs and rejects everything else" do
      assert valid_uuid?(Ecto.UUID.generate())
      # uppercase canonical still dumps
      assert valid_uuid?(String.upcase(Ecto.UUID.generate()))

      refute valid_uuid?(nil)
      refute valid_uuid?("not-a-uuid")
      # non-binary
      refute valid_uuid?(:an_atom)
      # raw 16-byte binary
      refute valid_uuid?(<<0::128>>)
    end
  end
end
