defmodule Lightning.Credentials.AuditTest do
  use Lightning.DataCase, async: true

  alias Ecto.Changeset
  alias Lightning.Credentials.{Audit, Credential}

  import Lightning.{AccountsFixtures, CredentialsFixtures}

  describe "event/4" do
    test "generates 'created' audit trail entries" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, body: %{"my-secret" => "value"})

      {:ok, audit} =
        Audit.event("created", credential.id, user)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id
      assert %{before: nil, after: nil} = audit.changes
      assert audit.event == "created"
      assert audit.actor_id == user.id
      assert audit.actor_type == :user
    end

    test "generates 'updated' audit trail entries" do
      user = user_fixture()

      credential = credential_fixture(user_id: user.id, body: %{})

      changeset =
        Credential.changeset(credential, %{body: %{"my-secret" => "value"}})

      {:ok, audit} =
        Audit.event("updated", credential.id, user, changeset)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id

      # Check that the body attribute is encrypted in audit records too.
      # We can only test the beginning of the encrypted string as the
      # algorithm include randomness or padding of some sort.
      # %{}
      assert audit.changes.before.body =~ "AQpBRVMuR0NNLlYx"
      # %{"my-secret" => "value}
      assert audit.changes.after.body =~ "AQpBRVMuR0NNLlYx"

      assert audit.event == "updated"
      assert audit.actor_id == user.id
      assert audit.actor_type == :user
    end

    test "generates 'deleted' audit trail entries" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, body: %{"my-secret" => "value"})

      {:ok, audit} =
        Audit.event("deleted", credential.id, user)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id

      assert audit.changes == %Lightning.Auditing.Audit.Changes{
               before: nil,
               after: nil
             }

      assert audit.event == "deleted"
      assert audit.actor_id == user.id
      assert audit.actor_type == :user
    end
  end

  describe ".user_initiated_event" do
    test "generates changeset for event if user association is present" do
      %{id: user_id} = user_fixture()

      %{id: credential_id} =
        credential =
        credential_fixture(user_id: user_id, body: %{}) |> Repo.preload(:user)

      changeset =
        Credential.changeset(credential, %{body: %{"my-secret" => "value"}})

      audit_changeset =
        Audit.user_initiated_event("updated", credential, changeset)

      assert %{
               changes: %{
                 event: "updated",
                 item_id: ^credential_id,
                 item_type: "credential",
                 actor_id: ^user_id,
                 actor_type: :user,
                 changes: changes
               }
             } = audit_changeset

      # Check that the body attribute is encrypted in audit records too.
      # We can only test the beginning of the encrypted string as the
      # algorithm include randomness or padding of some sort.
      # %{}
      assert Changeset.get_change(changes, :before).body =~ "AQpBRVMuR0NNLlYx"
      # %{"my-secret" => "value}
      assert Changeset.get_change(changes, :after).body =~ "AQpBRVMuR0NNLlYx"
    end

    test "generates changeset for event if user association is absent" do
      %{id: user_id} = user_fixture()

      %{id: credential_id} =
        credential =
        credential_fixture(user_id: user_id, body: %{})

      changeset =
        Credential.changeset(credential, %{body: %{"my-secret" => "value"}})

      audit_changeset =
        Audit.user_initiated_event("updated", credential, changeset)

      assert %{
               changes: %{
                 event: "updated",
                 item_id: ^credential_id,
                 item_type: "credential",
                 actor_id: ^user_id,
                 actor_type: :user,
                 changes: changes
               }
             } = audit_changeset

      # Check that the body attribute is encrypted in audit records too.
      # We can only test the beginning of the encrypted string as the
      # algorithm include randomness or padding of some sort.
      # %{}
      assert Changeset.get_change(changes, :before).body =~ "AQpBRVMuR0NNLlYx"
      # %{"my-secret" => "value}
      assert Changeset.get_change(changes, :after).body =~ "AQpBRVMuR0NNLlYx"
    end

    test "generates changeset for event where changes are absent" do
      %{id: user_id} = user_fixture()

      %{id: credential_id} =
        credential =
        credential_fixture(user_id: user_id, body: %{})

      audit_changeset = Audit.user_initiated_event("deleted", credential)

      assert %{
               changes: %{
                 event: "deleted",
                 item_id: ^credential_id,
                 item_type: "credential",
                 actor_id: ^user_id,
                 actor_type: :user,
                 changes: %{
                   changes: %{}
                 }
               }
             } = audit_changeset
    end
  end
end
