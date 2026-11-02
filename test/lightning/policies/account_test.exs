defmodule Lightning.Policies.AccountTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Policies.Permissions
  alias Lightning.Scope

  @step_up_actions [:create_own_token, :enable_mfa, :disable_mfa]
  @session_actions [
    :read_own_mfa,
    :start_mfa,
    :disconnect_github,
    :list_github_repos
  ]
  @people_actions [:list_own_tokens, :revoke_own_token]

  defp scopes(user) do
    {account, _key} = Lightning.ServiceAccountHelpers.service_account_with_key()
    later = DateTime.add(DateTime.utc_now(), 300)

    %{
      session: Scope.new(user, token_kind: :session),
      stepped_up: Scope.new(user, token_kind: :session, stepped_up_until: later),
      personal: Scope.new(user, token_kind: :personal_access_token),
      service_account: Scope.new(account, token_kind: :access_token),
      repo_connection:
        Scope.new(insert(:project_repo_connection),
          token_kind: :repo_connection
        )
    }
  end

  defp permit(action, scope), do: Permissions.permit(:account, action, scope)

  test "a person's tokens are listed and revoked on either of their tokens, and by nothing else" do
    scopes = scopes(insert(:user))

    for action <- @people_actions do
      for kind <- [:session, :stepped_up, :personal],
          do: assert(permit(action, scopes[kind]) == :ok)

      for kind <- [:service_account, :repo_connection],
          do: assert(permit(action, scopes[kind]) == {:error, :forbidden})
    end
  end

  test "MFA and GitHub need a session token" do
    scopes = scopes(insert(:user))

    for action <- @session_actions do
      for kind <- [:session, :stepped_up],
          do: assert(permit(action, scopes[kind]) == :ok)

      for kind <- [:personal, :service_account, :repo_connection],
          do: assert(permit(action, scopes[kind]) == {:error, :forbidden})
    end
  end

  test "creating a token and turning MFA on or off need a stepped-up session" do
    scopes = scopes(insert(:user))

    for action <- @step_up_actions do
      assert permit(action, scopes.stepped_up) == :ok
      assert permit(action, scopes.session) == {:error, :step_up_required}

      for kind <- [:personal, :service_account, :repo_connection],
          do: assert(permit(action, scopes[kind]) == {:error, :forbidden})
    end
  end

  test "making backup codes needs a stepped-up session and MFA on" do
    with_mfa = scopes(insert(:user, mfa_enabled: true))
    without = scopes(insert(:user))

    assert permit(:regenerate_backup_codes, with_mfa.stepped_up) == :ok

    assert permit(:regenerate_backup_codes, with_mfa.session) ==
             {:error, :step_up_required}

    assert permit(:regenerate_backup_codes, without.stepped_up) ==
             {:error, :forbidden}

    assert permit(:regenerate_backup_codes, with_mfa.personal) ==
             {:error, :forbidden}
  end

  test "the sign-in provider is a superuser's, on either of their tokens" do
    superuser = scopes(insert(:user, role: :superuser))
    user = scopes(insert(:user))

    for action <- [:read_auth_provider, :write_auth_provider] do
      for kind <- [:session, :personal] do
        assert Permissions.permit(:auth_providers, action, superuser[kind]) ==
                 :ok

        assert Permissions.permit(:auth_providers, action, user[kind]) ==
                 {:error, :forbidden}
      end

      for kind <- [:service_account, :repo_connection] do
        assert Permissions.permit(:auth_providers, action, superuser[kind]) ==
                 {:error, :forbidden}
      end
    end
  end
end
