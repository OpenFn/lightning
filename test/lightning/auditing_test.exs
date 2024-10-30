defmodule Lightning.AuditingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User
  alias Lightning.Auditing
  alias Lightning.Auditing.Audit

  describe "list_all/1" do
    setup do
      now = DateTime.utc_now()

      user = insert(:user)
      _other_user = insert(:user)

      [user_event_3, user_event_4] = insert_events_for_struct(user, now)

      %{
        user: user,
        user_event_3: user_event_3,
        user_event_4: user_event_4
      }
    end

    test "returns a paginated reverse-chronological list of audit entries", %{
      user_event_3: user_event_3,
      user_event_4: user_event_4
    } do
      %{entries: [%{id: id_1}, %{id: id_2}]} =
        Auditing.list_all(page: 2, page_size: 2)

      assert id_1 == user_event_3.id
      assert id_2 == user_event_4.id
    end

    test "returns full audit entry for an user event", %{
      user: %{
        first_name: first_name,
        last_name: last_name,
        email: email
      },
      user_event_3: user_event_3
    } do
      %{
        id: id,
        event: event,
        item_id: item_id,
        item_type: item_type,
        actor_id: actor_id,
        actor_type: actor_type,
        changes: changes
      } = user_event_3

      actor_display_label = "#{first_name} #{last_name}"

      %{entries: [entry, _]} =
        Auditing.list_all(page: 2, page_size: 2)

      assert %{
               id: ^id,
               actor_display_identifier: ^email,
               actor_display_label: ^actor_display_label,
               actor_id: ^actor_id,
               actor_type: ^actor_type,
               item_id: ^item_id,
               item_type: ^item_type,
               event: ^event,
               changes: ^changes
             } = entry
    end

    test "returns full audit entry for a user event if user no longer exists", %{
      user: user,
      user_event_3: user_event_3
    } do
      %{
        id: id,
        event: event,
        item_id: item_id,
        item_type: item_type,
        actor_id: actor_id,
        actor_type: actor_type,
        changes: changes
      } = user_event_3

      user |> Repo.delete()

      %{entries: [entry, _]} =
        Auditing.list_all(page: 2, page_size: 2)

      assert %{
               id: ^id,
               actor_id: ^actor_id,
               actor_display_identifier: nil,
               actor_display_label: "(User deleted)",
               actor_type: ^actor_type,
               item_id: ^item_id,
               item_type: ^item_type,
               event: ^event,
               changes: ^changes
             } = entry
    end

    defp insert_events_for_struct(%User{id: id}, now) do
      insert_events(id, :user, now, 0)
    end

    defp insert_events(actor_id, actor_type, now, struct_offset) do
      [-10, -20, -30, -40, -50, -60, -70, -80]
      |> Enum.shuffle()
      |> Enum.map(fn base_offset ->
        insert(
          :audit,
          actor_id: actor_id,
          actor_type: actor_type,
          inserted_at: DateTime.add(now, base_offset + struct_offset, :second)
        )
      end)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.slice(2, 2)
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
                 actor_type: :project_repo_connection
               },
               valid?: true
             } = audit_changeset

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :before) == %{name: "test"}
      assert Ecto.Changeset.get_change(changes, :after) == %{name: "test two"}
    end

    test "returns a changeset when the changes are a map", %{
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
                 actor_type: :project_repo_connection
               },
               valid?: true
             } = audit_changeset

      changes = Ecto.Changeset.get_embed(audit_changeset, :changes)
      assert Ecto.Changeset.get_change(changes, :before) == %{foo: "bar"}
      assert Ecto.Changeset.get_change(changes, :after) == %{foo: "baz"}
    end

    test "maps actor structs to actor types" do
      item_id = Ecto.UUID.generate()
      changes = %{before: %{foo: "bar"}, after: %{foo: "baz"}}

      assert %{changes: %{actor_type: :user}} =
               Audit.event(
                 "credential",
                 "updated",
                 item_id,
                 insert(:user),
                 changes
               )

      assert %{changes: %{actor_type: :project_repo_connection}} =
               Audit.event(
                 "credential",
                 "updated",
                 item_id,
                 insert(:project_repo_connection),
                 changes
               )

      assert %{changes: %{actor_type: :trigger}} =
               Audit.event(
                 "credential",
                 "updated",
                 item_id,
                 insert(:trigger),
                 changes
               )
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
          %{},
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
        actor_type: :project_repo_connection,
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
                 actor_type: :project_repo_connection,
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
