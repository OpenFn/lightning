defmodule Lightning.Accounts.NotificationTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.Notification
  import Lightning.AccountsFixtures

  describe "changeset/2" do
    test "changeset/2 returns a notification changeset" do
      notification = %Notification{
        event: "email-sent",
        user_id: user_fixture().id,
        metadata: %{}
      }

      assert %Ecto.Changeset{required: [:event, :user_id]} =
               Notification.changeset(notification)
    end
  end

  describe "notifications" do
    test "create_notification/1 with valid data creates a notification" do
      id = user_fixture().id

      assert {:ok, %Notification{} = notification} =
               Lightning.Notifications.create_notification(%{
                 event: "event",
                 user_id: id
               })

      assert notification.event == "event"
      assert notification.user_id == id
    end

    test "create_notification/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Lightning.Notifications.create_notification(%{
                 event: nil,
                 user_id: nil
               })
    end
  end
end
