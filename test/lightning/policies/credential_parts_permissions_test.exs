defmodule Lightning.Policies.CredentialPartsPermissionsTest do
  @moduledoc """
  Who may schedule a credential's deletion, change its environments, link it
  to a project or unlink it, and transfer it.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Credential
  alias Lightning.Policies.Credentials
  alias Lightning.Scope

  setup do
    {account, _key} = Lightning.ServiceAccountHelpers.service_account_with_key()
    owner = insert(:user)

    %{
      owner: owner,
      credential: insert(:credential, user: owner),
      operator: %{account | grants: MapSet.new(["credentials:write"])},
      bare: %{account | grants: MapSet.new(["projects:write"])}
    }
  end

  @owner_or_operator [
    :schedule_credential_deletion,
    :edit_credential_environments,
    :link_credential
  ]

  test "scheduling, environments and linking are for the owner and an operator with the grant",
       %{owner: owner, credential: credential, operator: operator, bare: bare} do
    callers = [
      owner,
      insert(:user),
      insert(:user, role: :superuser),
      operator,
      bare
    ]

    for action <- @owner_or_operator do
      assert Enum.map(callers, &Credentials.authorize(action, &1, credential)) ==
               [
                 true,
                 false,
                 false,
                 true,
                 {:error, {:insufficient_scope, "credentials:write"}}
               ],
             "#{action}"
    end
  end

  test "asked with no credential, only an operator may act on every credential",
       %{owner: owner, operator: operator} do
    for action <- @owner_or_operator do
      assert Credentials.authorize(action, Scope.new(operator), nil) == true
      assert Credentials.authorize(action, Scope.new(owner), nil) == false
    end

    assert Credentials.authorize(:transfer_credential, Scope.new(owner), nil) ==
             false
  end

  test "a scheduled credential may still be scheduled or cancelled, but refuses environments, linking and transfer",
       %{owner: owner, credential: credential, operator: operator} do
    scheduled = %Credential{
      credential
      | scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    for actor <- [owner, operator] do
      assert Credentials.authorize(
               :schedule_credential_deletion,
               actor,
               scheduled
             ) == true

      for action <- [:edit_credential_environments, :link_credential] do
        assert Credentials.authorize(action, actor, scheduled) ==
                 {:error, :scheduled_for_deletion}
      end
    end

    assert Credentials.authorize(
             :transfer_credential,
             Scope.new(owner, token_kind: :personal_access_token),
             scheduled
           ) == {:error, :scheduled_for_deletion}

    assert Credentials.authorize(:link_credential, insert(:user), scheduled) ==
             false
  end

  test "transferring is only for the owner, on a person's token, and the service account is refused before any credential",
       %{owner: owner, credential: credential, operator: operator} do
    for token_kind <- [:personal_access_token, :session] do
      assert Credentials.authorize(
               :transfer_credential,
               Scope.new(owner, token_kind: token_kind),
               credential
             ) == true
    end

    assert Credentials.authorize(
             :transfer_credential,
             Scope.new(insert(:user)),
             credential
           ) == false

    for subject <- [:before_target, credential] do
      assert Credentials.authorize(
               :transfer_credential,
               Scope.new(operator, token_kind: :access_token),
               subject
             ) == false
    end
  end

  describe "unlinking" do
    setup %{owner: owner, credential: credential} do
      [project_owner, admin, editor] = insert_list(3, :user)

      project =
        insert(:project,
          project_users: [
            %{user: project_owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: editor, role: :editor},
            %{user: owner, role: :viewer}
          ]
        )

      link =
        insert(:project_credential, project: project, credential: credential)
        |> Repo.preload(:credential)

      %{
        link: link,
        project_owner: project_owner,
        admin: admin,
        editor: editor,
        project: project
      }
    end

    test "is for the credential's owner, a project owner or admin, and an operator",
         ctx do
      callers = [
        ctx.owner,
        ctx.project_owner,
        ctx.admin,
        ctx.editor,
        insert(:user),
        ctx.operator
      ]

      assert Enum.map(
               callers,
               &Credentials.authorize(:unlink_credential, &1, ctx.link)
             ) ==
               [true, true, true, false, false, true]
    end

    test "a project that requires MFA refuses an unenrolled owner of the credential",
         ctx do
      ctx.project
      |> Ecto.Changeset.change(requires_mfa: true)
      |> Repo.update!()

      refute Credentials.authorize(:unlink_credential, ctx.owner, ctx.link)
    end
  end
end
