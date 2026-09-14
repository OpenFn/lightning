defmodule Lightning.Projects.MailRecipientsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.MailRecipients

  describe "may_receive?/2" do
    test "a live member of a project with no MFA requirement may receive" do
      user = insert(:user)
      project = project_with(user)

      assert MailRecipients.may_receive?(project, user)
    end

    test "a disabled account may not" do
      user = insert(:user, disabled: true)
      project = project_with(user)

      refute MailRecipients.may_receive?(project, user)
    end

    test "an account scheduled for deletion may not" do
      user = insert(:user, scheduled_deletion: DateTime.utc_now(:second))
      project = project_with(user)

      refute MailRecipients.may_receive?(project, user)
    end

    # `locked_out?` is the same predicate the request path refuses on, so the
    # set turned away here is exactly the set already shut out of the app. An
    # unverified address is also not known to belong to the member.
    test "an account barred pending email confirmation may not" do
      require_email_verification!()
      user = unconfirmed_user(hours_ago: 50)
      project = project_with(user)

      refute MailRecipients.may_receive?(project, user)
    end

    test "a confirmed account may, with the same requirement in force" do
      require_email_verification!()

      user =
        unconfirmed_user(hours_ago: 50, confirmed_at: DateTime.utc_now(:second))

      project = project_with(user)

      assert MailRecipients.may_receive?(project, user)
    end

    test "an unconfirmed account inside the grace period may" do
      require_email_verification!()
      user = unconfirmed_user(hours_ago: 1)
      project = project_with(user)

      assert MailRecipients.may_receive?(project, user)
    end

    test "an enrolled member of a project that requires MFA may receive" do
      user = insert(:user, mfa_enabled: true)
      project = project_with(user, requires_mfa: true)

      assert MailRecipients.may_receive?(project, user)
    end

    test "a member who has not enrolled may not, when the project requires it" do
      user = insert(:user, mfa_enabled: false)
      project = project_with(user, requires_mfa: true)

      refute MailRecipients.may_receive?(project, user)
    end

    # Not "not yet decided" — an unset flag is not enrolled.
    test "an unset enrolment flag may not, when the project requires it" do
      user = insert(:user, mfa_enabled: nil)
      project = project_with(user, requires_mfa: true)

      refute MailRecipients.may_receive?(project, user)
    end

    # The mail queries all select members, so this never fires today. It is
    # here so the next recipient query cannot make a non-member reachable by
    # passing one in.
    test "someone with no standing in the project may not" do
      refute MailRecipients.may_receive?(insert(:project), insert(:user))
    end

    # The digest query filters this on the project side already; the alert path
    # does not. The rule refuses it wherever it is asked from.
    test "a live member of a project scheduled for deletion may not" do
      user = insert(:user)

      project =
        project_with(user,
          scheduled_deletion: DateTime.utc_now(:second)
        )

      refute MailRecipients.may_receive?(project, user)
    end
  end

  defp project_with(user, attrs \\ []) do
    attrs
    |> Keyword.put(:project_users, [%{user_id: user.id, role: :editor}])
    |> then(&insert(:project, &1))
  end

  defp require_email_verification! do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> true
      other -> Lightning.Config.API.check_flag?(other)
    end)
  end

  defp unconfirmed_user(opts) do
    {hours, attrs} = Keyword.pop!(opts, :hours_ago)

    insert(
      :user,
      Keyword.merge(
        [
          confirmed_at: nil,
          inserted_at: DateTime.utc_now(:second) |> DateTime.add(-hours, :hour)
        ],
        attrs
      )
    )
  end
end
