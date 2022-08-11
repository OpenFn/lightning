defmodule OpenFn.DbCleanupServiceTest do
  test "purging user removes only that user and their credentials", %{
    project: project,
    supportable_project: other_project,
    owner: owner,
    collaborator: collaborator
  } do
    insert(:credential, user: owner.user, projects: [project])
    insert(:credential, user: collaborator.user, projects: [project])

    assert 2 == Repo.all(Credential) |> Enum.count()
    assert 4 == Repo.all(User) |> Enum.count()

    :ok = PurgeUsersData.purge_user(owner.user.id)

    remaining_creds = Repo.all(Credential)
    remaining_users = Repo.all(User)

    assert 1 == Enum.count(remaining_creds)
    assert 3 == Enum.count(remaining_users)

    assert remaining_creds |> Enum.any?(fn x -> x.user_id == owner.user.id end) |> Kernel.not()

    assert 1 ==
             remaining_creds
             |> Enum.filter(fn x -> x.user_id == collaborator.user.id end)
             |> Enum.count()

    assert remaining_users |> Enum.any?(fn x -> x.id == owner.user.id end) |> Kernel.not()

    assert 1 ==
             remaining_users
             |> Enum.filter(fn x -> x.id == collaborator.user.id end)
             |> Enum.count()
  end
end
