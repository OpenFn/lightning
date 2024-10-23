defmodule Lightning.AuditingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing
  alias Lightning.Auditing.Audit
  import Lightning.CredentialsFixtures

  describe "list_all/1" do
    test "When a credential is created, it should appear in the audit trail" do
      %{id: credential_id} = credential_fixture()

      %{entries: [entry]} = Auditing.list_all()

      assert entry.item_id == credential_id
    end
  end

  describe "Audit.event/6" do
    test "returns no_changes when there are no changes" do
      changeset =
        Ecto.Changeset.change(%Lightning.Credentials.Credential{}, %{})

      assert :no_changes ==
               Audit.event(
                 "credential",
                 "updated",
                 Ecto.UUID.generate(),
                 Ecto.UUID.generate(),
                 changeset
               )
    end

    test "returns a changeset when there are changes" do
      item_id = Ecto.UUID.generate()
      actor_id = Ecto.UUID.generate()

      changeset =
        Ecto.Changeset.change(
          %Lightning.Credentials.Credential{name: "test"},
          %{name: "test two"}
        )

      audit_changeset =
        Audit.event(
          "credential",
          "updated",
          item_id,
          actor_id,
          changeset
        )

      assert %{
               changes: %{
                 item_type: "credential",
                 event: "updated",
                 item_id: ^item_id,
                 actor_id: ^actor_id
               }
             } = audit_changeset

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :before) == %{name: "test"}
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "test two"}
    end

    test "'created' event sets before changes to nil" do
      changeset =
        Ecto.Changeset.change(%Lightning.Credentials.Credential{}, %{
          name: "test"
        })

      audit_changeset =
        Audit.event(
          "credential",
          "created",
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          changeset
        )

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert changes |> Ecto.Changeset.get_change(:before) |> is_nil()
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "test"}

      audit_changeset =
        Audit.event(
          "credential",
          "updated",
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          changeset
        )

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :before) == %{name: nil}
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "test"}
    end

    test "changes can be updated using the callback function" do
      changeset =
        Ecto.Changeset.change(%Lightning.Credentials.Credential{}, %{
          name: "test"
        })

      update_fun = fn changes ->
        Map.update!(changes, :name, &String.upcase/1)
      end

      audit_changeset =
        Audit.event(
          "credential",
          "created",
          Ecto.UUID.generate(),
          Ecto.UUID.generate(),
          changeset,
          update_fun
        )

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "TEST"}
    end
  end
end
