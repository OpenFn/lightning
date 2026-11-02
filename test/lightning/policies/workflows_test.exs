defmodule Lightning.Policies.WorkflowsTest do
  @moduledoc """
  The workflow API actions on a `%Scope{}` are for people only. Within that,
  deleting takes an editor's role, reading snapshots and versions any member's,
  publishing a template a support user's, and listing templates nothing more.
  """
  use Lightning.DataCase, async: true

  import Lightning.ServiceAccountHelpers, only: [service_account_with_key: 0]

  alias Lightning.Policies.Permissions
  alias Lightning.Scope

  @actions [
    :delete_workflow,
    :read_workflow_history,
    :publish_template,
    :list_templates
  ]

  setup do
    [owner, admin, editor, viewer, stranger] = insert_list(5, :user)
    support_member = insert(:user, support_user: true)
    support_outsider = insert(:user, support_user: true)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer},
          %{user: support_member, role: :viewer}
        ]
      )

    %{
      project: project,
      people: %{
        owner: owner,
        admin: admin,
        editor: editor,
        viewer: viewer,
        stranger: stranger,
        support_member: support_member,
        support_outsider: support_outsider
      }
    }
  end

  test "people's roles decide, on a personal access token and a session token alike",
       %{project: project, people: people} do
    for token_kind <- [:personal_access_token, :session],
        {who, expected} <- [
          {:owner, {true, true, false, true}},
          {:admin, {true, true, false, true}},
          {:editor, {true, true, false, true}},
          {:viewer, {false, true, false, true}},
          {:stranger, {false, false, false, true}},
          {:support_member, {false, true, true, true}},
          {:support_outsider, {false, false, false, true}}
        ] do
      scope = scope(people[who], project, token_kind)

      assert {permit(:delete_workflow, scope, project),
              permit(:read_workflow_history, scope, project),
              permit(:publish_template, scope, project),
              permit(:list_templates, scope, nil)} == expected,
             "#{who} on a #{token_kind} token"
    end
  end

  test "the service account and a repo connection are refused before anything is looked up, whatever their grants",
       %{project: project} do
    {account, _key} = service_account_with_key()

    account = %{
      account
      | grants: MapSet.new(Lightning.ServiceAccount.AccessToken.scopes())
    }

    repo_connection = insert(:project_repo_connection, project: project)

    for actor <- [account, repo_connection], action <- @actions do
      assert Permissions.permit(:workflows, action, Scope.new(actor)) ==
               {:error, :forbidden},
             "#{action} for #{inspect(actor.__struct__)}"
    end
  end

  defp scope(user, project, token_kind) do
    {:ok, scope} = Scope.fetch(Scope.new(user, token_kind: token_kind), project)
    scope
  end

  defp permit(action, scope, subject),
    do: Permissions.permit(:workflows, action, scope, subject) == :ok
end
