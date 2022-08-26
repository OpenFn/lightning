defmodule Lightning.Accounts.UserNotifierTest do
  use Lightning.DataCase, async: true

  import Swoosh.TestAssertions

  alias Lightning.Accounts.{UserNotifier, User}

  describe "Notification emails" do
    test "send_deletion_notification_email/1" do
      {:ok, email} =
        UserNotifier.send_deletion_notification_email(%User{
          email: "real@email.com"
        })

      assert_email_sent(email)
    end
  end
end
