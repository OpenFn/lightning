defmodule Lightning.Policies.HistoryTest do
  @moduledoc """
  The history actions are for people only. Within that, running and changing
  history takes an editor's role, and reading it any member's.
  """
  use Lightning.DataCase, async: true

  import Lightning.ServiceAccountHelpers, only: [service_account_with_key: 0]

  alias Lightning.Policies.Permissions
  alias Lightning.Scope

  setup do
    [owner, admin, editor, viewer, stranger] = insert_list(5, :user)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    %{
      project: project,
      people: %{
        owner: owner,
        admin: admin,
        editor: editor,
        viewer: viewer,
        stranger: stranger
      }
    }
  end

  test "people's roles decide, on a personal access token and a session token alike",
       %{project: project, people: people} do
    for token_kind <- [:personal, :session],
        {who, run?, read?} <- [
          {:owner, true, true},
          {:admin, true, true},
          {:editor, true, true},
          {:viewer, false, true},
          {:stranger, false, false}
        ] do
      scope = scope(people[who], project, token_kind)

      assert {permit(:run_workflow, scope, project),
              permit(:read_history, scope, project)} ==
               {run?, read?},
             "#{who} on a #{token_kind} token"
    end
  end

  test "the service account is refused before anything is looked up, whatever its grants",
       %{project: project} do
    {account, _key} = service_account_with_key()

    account = %{
      account
      | grants: MapSet.new(Lightning.ServiceAccount.AccessToken.scopes())
    }

    for action <- [:run_workflow, :read_history] do
      assert Permissions.permit(:history, action, Scope.new(account)) ==
               {:error, :forbidden}

      {:ok, scope} = Scope.fetch(account, project)
      refute permit(action, scope, project)
    end
  end

  defp scope(user, project, token_kind) do
    {:ok, scope} = Scope.fetch(Scope.new(user, token_kind: token_kind), project)
    scope
  end

  defp permit(action, scope, project),
    do: Permissions.permit(:history, action, scope, project) == :ok
end
