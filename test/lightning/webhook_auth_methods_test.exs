defmodule Lightning.WebhookAuthMethodsTest do
  use Lightning.DataCase, async: true
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethodAudit
  import Lightning.Factories

  describe "create_auth_method/2" do
    setup do
      project = insert(:project)

      valid_attrs = %{
        name: "some_name",
        auth_type: "basic",
        username: "username",
        password: "password",
        project_id: project.id
      }

      invalid_attrs = %{
        invalid: "attributes"
      }

      {:ok,
       valid_attrs: valid_attrs, invalid_attrs: invalid_attrs, project: project}
    end

    test "creates a webhook auth method with valid attributes", %{
      valid_attrs: valid_attrs
    } do
      assert_creation_with(
        valid_attrs,
        :basic,
        "some_name",
        "username",
        "password"
      )

      Map.merge(valid_attrs, %{
        name: "some_other_name",
        auth_type: "api"
      })
      |> assert_creation_with(:api, "some_other_name", nil, nil)
    end

    test "saves the audit after successfull creation", %{
      valid_attrs: valid_attrs
    } do
      user = insert(:user)

      {:ok, auth_method} =
        WebhookAuthMethods.create_auth_method(valid_attrs, actor: user)

      assert Repo.get_by(WebhookAuthMethodAudit.base_query(),
               item_id: auth_method.id,
               event: "created",
               actor_id: user.id
             )
    end

    test "returns error when attributes are invalid", %{
      invalid_attrs: invalid_attrs
    } do
      assert {:error, _} =
               WebhookAuthMethods.create_auth_method(invalid_attrs,
                 actor: insert(:user)
               )
    end

    defp assert_creation_with(attrs, auth_type, name, username, password) do
      assert {:ok, auth_method} =
               WebhookAuthMethods.create_auth_method(attrs, actor: insert(:user))

      assert auth_method.name == name
      assert auth_method.auth_type == auth_type
      assert auth_method.username == username

      if password do
        assert auth_method.password == password
      else
        refute auth_method.password
      end

      if auth_type == :api do
        assert auth_method.api_key
      else
        refute auth_method.api_key
      end
    end
  end

  describe "create_auth_method/3" do
    test "creates and associates the authmethod with the trigger successfully" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow)
      user = insert(:user)

      {:ok, auth_method} =
        WebhookAuthMethods.create_auth_method(
          trigger,
          %{
            name: "some_name",
            auth_type: "basic",
            username: "username",
            password: "password",
            project_id: project.id
          },
          actor: user
        )

      assert %{
               auth_type: :basic,
               username: "username",
               password: "password",
               api_key: nil
             } = auth_method

      %{webhook_auth_methods: [associated_auth_method]} =
        Lightning.Repo.preload(trigger, :webhook_auth_methods)

      assert associated_auth_method.id == auth_method.id

      # saves 2 audit records
      # created
      assert Repo.get_by(WebhookAuthMethodAudit.base_query(),
               item_id: auth_method.id,
               event: "created",
               actor_id: user.id
             )

      # added to trigger
      added_to_trigger =
        Repo.get_by(WebhookAuthMethodAudit.base_query(),
          item_id: auth_method.id,
          event: "added_to_trigger",
          actor_id: user.id
        )

      assert added_to_trigger.changes == %Lightning.Auditing.Model.Changes{
               before: %{"trigger_id" => nil},
               after: %{"trigger_id" => trigger.id}
             }
    end
  end

  describe "update_auth_method/3" do
    setup do
      auth_method = insert(:webhook_auth_method)
      {:ok, auth_method: auth_method}
    end

    test "updates the webhook auth method with valid attributes", %{
      auth_method: auth_method
    } do
      user = insert(:user)

      assert {:ok, new_auth_method} =
               WebhookAuthMethods.update_auth_method(
                 auth_method,
                 %{
                   name: "new_name"
                 },
                 actor: user
               )

      assert new_auth_method.name == "new_name"

      # audit is created
      audit =
        Repo.get_by(WebhookAuthMethodAudit.base_query(),
          item_id: auth_method.id,
          event: "updated",
          actor_id: user.id
        )

      assert audit.changes == %Lightning.Auditing.Model.Changes{
               before: %{"name" => auth_method.name},
               after: %{"name" => new_auth_method.name}
             }
    end

    test "returns error when attributes are invalid", %{auth_method: auth_method} do
      user = insert(:user)

      assert {:error, _} =
               WebhookAuthMethods.update_auth_method(
                 auth_method,
                 %{
                   name: nil
                 },
                 actor: user
               )
    end
  end

  describe "update_trigger_auth_methods/3" do
    test "updates a trigger with no auth methods correctly" do
      trigger = insert(:trigger)
      auth_method = insert(:webhook_auth_method)
      user = insert(:user)

      assert {:ok, updated_trigger} =
               WebhookAuthMethods.update_trigger_auth_methods(
                 trigger,
                 [
                   auth_method
                 ],
                 actor: user
               )

      assert updated_trigger.webhook_auth_methods == [auth_method]

      # audit is created
      added_to_trigger =
        Repo.get_by(WebhookAuthMethodAudit.base_query(),
          item_id: auth_method.id,
          event: "added_to_trigger",
          actor_id: user.id
        )

      assert added_to_trigger.changes == %Lightning.Auditing.Model.Changes{
               before: %{"trigger_id" => nil},
               after: %{"trigger_id" => trigger.id}
             }
    end

    test "replaces the attached auth methods" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)
      user = insert(:user)

      trigger =
        insert(:trigger,
          workflow: workflow,
          webhook_auth_methods:
            build_list(3, :webhook_auth_method, project: project)
        )

      assert length(trigger.webhook_auth_methods) == 3

      auth_method = insert(:webhook_auth_method)

      assert {:ok, updated_trigger} =
               WebhookAuthMethods.update_trigger_auth_methods(
                 trigger,
                 [
                   auth_method
                 ],
                 actor: user
               )

      updated_trigger =
        Lightning.Repo.preload(updated_trigger, :webhook_auth_methods)

      assert updated_trigger.webhook_auth_methods == [auth_method]

      # audit is created for adding to trigger
      for auth_method <- updated_trigger.webhook_auth_methods do
        audit =
          Repo.get_by(WebhookAuthMethodAudit.base_query(),
            item_id: auth_method.id,
            event: "added_to_trigger",
            actor_id: user.id
          )

        assert audit.changes == %Lightning.Auditing.Model.Changes{
                 before: %{"trigger_id" => nil},
                 after: %{"trigger_id" => trigger.id}
               }
      end

      # audit is created for removing from trigger
      for auth_method <- trigger.webhook_auth_methods do
        audit =
          Repo.get_by(WebhookAuthMethodAudit.base_query(),
            item_id: auth_method.id,
            event: "removed_from_trigger",
            actor_id: user.id
          )

        assert audit.changes == %Lightning.Auditing.Model.Changes{
                 after: %{"trigger_id" => nil},
                 before: %{"trigger_id" => trigger.id}
               }
      end
    end
  end

  describe "list_for_project/1" do
    test "lists all webhook auth methods for a given project" do
      project = insert(:project)
      insert_list(3, :webhook_auth_method, project: project)

      assert 3 = length(WebhookAuthMethods.list_for_project(project))
    end

    test "returns an empty list if there are no auth methods for a given project" do
      project = insert(:project)
      assert [] = WebhookAuthMethods.list_for_project(project)
    end
  end

  describe "find_by_api_key/2" do
    test "retrieves the auth method by api_key and project_id" do
      auth_method = insert(:webhook_auth_method, api_key: "some_api_key")

      assert WebhookAuthMethods.find_by_api_key(
               "some_api_key",
               auth_method.project
             ) ==
               auth_method
               |> unload_relation(:project)
    end

    test "returns nil if there is no matching auth method" do
      project = insert(:project)

      assert is_nil(
               WebhookAuthMethods.find_by_api_key(
                 "non_existing_api_key",
                 project
               )
             )
    end
  end

  describe "find_by_username_and_password/3" do
    setup do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method, %{
          auth_type: :basic,
          name: "my_webhook_auth_method",
          username: "some_username",
          password: "hello password",
          project: project
        })

      {:ok, auth_method: auth_method, project: project}
    end

    test "retrieves the auth method if the username and password are valid", %{
      auth_method: auth_method,
      project: project
    } do
      result =
        WebhookAuthMethods.find_by_username_and_password(
          "some_username",
          "hello password",
          project
        )

      assert result.id == auth_method.id
    end

    test "returns nil if the password is invalid", %{
      project: project
    } do
      assert is_nil(
               WebhookAuthMethods.find_by_username_and_password(
                 "some_username",
                 "invalid_password",
                 project
               )
             )
    end
  end

  describe "find_by_id!/1" do
    test "retrieves the auth method by id" do
      auth_method = insert(:webhook_auth_method)

      assert WebhookAuthMethods.find_by_id!(auth_method.id) ==
               auth_method
               |> unload_relation(:project)
    end

    test "raises an error if there is no matching auth method" do
      assert_raise Ecto.NoResultsError, fn ->
        WebhookAuthMethods.find_by_id!(Ecto.UUID.generate())
      end
    end
  end

  describe "delete_auth_method/1" do
    test "deletes a Webhook Auth Method" do
      auth_method = insert(:webhook_auth_method)

      assert {:ok, _} = WebhookAuthMethods.delete_auth_method(auth_method)

      assert is_nil(
               Repo.get(Lightning.Workflows.WebhookAuthMethod, auth_method.id)
             )
    end
  end

  test "schedule_for_deletion/2 schedules a webhook auth method for deletion" do
    user = insert(:user)
    webhook_auth_method = insert(:webhook_auth_method)

    assert webhook_auth_method.scheduled_deletion == nil

    days = Application.get_env(:lightning, :purge_deleted_after_days, 0)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, changeset} =
      Lightning.WebhookAuthMethods.schedule_for_deletion(webhook_auth_method,
        actor: user
      )

    assert changeset.scheduled_deletion != nil

    assert Timex.diff(changeset.scheduled_deletion, now, :days) ==
             days

    # Check for audit log entry
    audit =
      Lightning.Auditing.list_all()
      |> Enum.find(fn audit ->
        audit.item_id == changeset.id and
          audit.event == "deleted" and
          audit.item_type == "webhook_auth_method"
      end)

    assert audit
    assert audit.actor_id == user.id
    assert audit.changes.before == %{"scheduled_deletion" => nil}

    # Truncate the fractional seconds from the audit log and append 'Z' for UTC
    audit_scheduled_deletion =
      String.split(audit.changes.after["scheduled_deletion"], ".")
      |> List.first()
      |> Kernel.<>("Z")

    # Assertion
    assert %{"scheduled_deletion" => audit_scheduled_deletion} == %{
             "scheduled_deletion" =>
               DateTime.to_iso8601(changeset.scheduled_deletion)
           }
  end

  test "schedule_for_deletion/2 returns error when webhook auth method is already scheduled for deletion" do
    user = insert(:user)

    webhook_auth_method =
      insert(:webhook_auth_method, scheduled_deletion: DateTime.utc_now())

    initial_audit_entries_count =
      Lightning.Auditing.list_all()
      |> Enum.count(fn audit ->
        audit.item_id == webhook_auth_method.id and audit.event == "deleted"
      end)

    result =
      Lightning.WebhookAuthMethods.schedule_for_deletion(webhook_auth_method,
        actor: user
      )

    assert {:error, _changeset} = result

    final_audit_entries_count =
      Lightning.Auditing.list_all()
      |> Enum.count(fn audit ->
        audit.item_id == webhook_auth_method.id and audit.event == "deleted"
      end)

    assert final_audit_entries_count == initial_audit_entries_count
  end
end
