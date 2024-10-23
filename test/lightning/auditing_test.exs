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
    setup do
      %{actor: insert(:project_repo_connection)}
    end

    test "returns no_changes when there are no changes", %{actor: actor} do
      changeset =
        Ecto.Changeset.change(%Lightning.Credentials.Credential{}, %{})

      assert :no_changes ==
               Audit.event(
                 "credential",
                 "updated",
                 Ecto.UUID.generate(),
                 actor,
                 changeset
               )
    end

    test "returns a changeset when there are changes", %{
      actor: %{id: actor_id} = actor
    } do
      item_id = Ecto.UUID.generate()

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
          actor,
          changeset
        )

      assert %{
               changes: %{
                 item_type: "credential",
                 event: "updated",
                 item_id: ^item_id,
                 actor_id: ^actor_id,
                 actor_type: "Lightning.VersionControl.ProjectRepoConnection"
               },
               valid?: true
             } = audit_changeset

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :before) == %{name: "test"}
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "test two"}
    end

    test "returns a changeset when he changes are a map", %{
      actor: %{id: actor_id} = actor
    } do
      item_id = Ecto.UUID.generate()

      changes = %{before: %{foo: "bar"}, after: %{foo: "baz"}}

      audit_changeset =
        Audit.event(
          "credential",
          "updated",
          item_id,
          actor,
          changes
        )

      assert %{
               changes: %{
                 item_type: "credential",
                 event: "updated",
                 item_id: ^item_id,
                 actor_id: ^actor_id,
                 actor_type: "Lightning.VersionControl.ProjectRepoConnection"
               },
               valid?: true
             } = audit_changeset

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :before) == %{foo: "bar"}
      assert Ecto.Changeset.get_change(changes, :after) == %{foo: "baz"}
    end

    test "'created' event sets before changes to nil", %{actor: actor} do
      changeset =
        Ecto.Changeset.change(%Lightning.Credentials.Credential{}, %{
          name: "test"
        })

      audit_changeset =
        Audit.event(
          "credential",
          "created",
          Ecto.UUID.generate(),
          actor,
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
          actor,
          changeset
        )

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :before) == %{name: nil}
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "test"}
    end

    test "changes can be updated using the callback function", %{actor: actor} do
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
          actor,
          changeset,
          update_fun
        )

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "TEST"}
    end
  end

  describe "Audit.changeset" do
    setup do
      actor_id = Ecto.UUID.generate()
      item_id = Ecto.UUID.generate()

      attrs = %{
        item_type: "credential",
        event: "updated",
        item_id: item_id,
        actor_id: actor_id,
        actor_type: "Lightning.VersionControl.ProjectRepoConnection",
        changes: %{
          before: %{name: "test"},
          after: %{name: "test two"}
        }
      }

      %{
        actor_id: actor_id,
        item_id: item_id,
        attrs: attrs
      }
    end

    test "returns a valid changeset", %{
      actor_id: actor_id,
      item_id: item_id,
      attrs: attrs
    } do
      changeset = %Audit{} |> Audit.changeset(attrs)

      assert %{
               changes: %{
                 item_type: "credential",
                 event: "updated",
                 item_id: ^item_id,
                 actor_id: ^actor_id,
                 actor_type: "Lightning.VersionControl.ProjectRepoConnection",
                 changes: changes
               },
               valid?: true
             } = changeset

      assert %{
               changes: %{
                 before: %{name: "test"},
                 after: %{name: "test two"}
               },
               valid?: true
             } = changes
    end

    test "is invalid if the event is absent", %{
      attrs: attrs
    } do
      changeset = %Audit{} |> Audit.changeset(attrs |> Map.delete(:event))

      assert %{
               errors: errors,
               valid?: false
             } = changeset

      assert errors == [{:event, {"can't be blank", [validation: :required]}}]
    end

    test "is invalid if the actor_id is absent", %{
      attrs: attrs
    } do
      changeset = %Audit{} |> Audit.changeset(attrs |> Map.delete(:actor_id))

      assert %{
               errors: errors,
               valid?: false
             } = changeset

      assert errors == [{:actor_id, {"can't be blank", [validation: :required]}}]
    end

    test "is invalid if the actor_type is absent", %{
      attrs: attrs
    } do
      changeset = %Audit{} |> Audit.changeset(attrs |> Map.delete(:actor_type))

      assert %{
               errors: errors,
               valid?: false
             } = changeset

      assert errors == [
               {:actor_type, {"can't be blank", [validation: :required]}}
             ]
    end
  end
end
