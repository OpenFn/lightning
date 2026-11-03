defmodule LightningWeb.API.KeychainCredentials.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiKeychainHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Repo

  @body %{"name" => "Not Checked", "path" => "nope", "x" => 1}

  defp reach(conn, :put, project_id, id),
    do: put_keychain(conn, project_id, id, @body)

  defp reach(conn, :delete, project_id, id),
    do: delete_keychain(conn, project_id, id)

  test "a caller the project refuses gets the same 403 for every id, and a permitted caller hears what is missing, malformed or held elsewhere",
       %{conn: conn} do
    [owner, admin, editor, viewer, stranger, short_of_mfa, support] =
      insert_list(7, :user)

    support = Repo.update!(Ecto.Changeset.change(support, support_user: true))
    superuser = insert(:user, role: :superuser)

    project =
      insert(:project,
        allow_support_access: true,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    mfa_project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: short_of_mfa, role: :owner}]
      )

    kept = insert(:keychain_credential, project: project)
    kept_mfa = insert(:keychain_credential, project: mfa_project)
    elsewhere = insert(:keychain_credential)

    {service_account, _account} =
      with_service_account(conn, ["credentials:write"])

    service_account =
      put_req_header(service_account, "accept", "application/json")

    malformed = [not_a_uuid_entry(%{"path" => "id"})]

    refused =
      for {user, project, keychain} <- [
            {stranger, project, kept},
            {editor, project, kept},
            {viewer, project, kept},
            {superuser, project, kept},
            {short_of_mfa, mfa_project, kept_mfa}
          ],
          id <- [
            keychain.id,
            Ecto.UUID.generate(),
            "not-a-uuid",
            elsewhere.id
          ],
          verb <- [:put, :delete],
          do:
            {session_conn(conn, user), verb, project.id, id, 403, :forbidden, []}

    people = [
      session_conn(conn, owner),
      session_conn(conn, admin),
      session_conn(conn, support)
    ]

    permitted =
      for caller <- [service_account | people],
          {verb, id, status, code, entries} <- [
            {:delete, Ecto.UUID.generate(), 404, :not_found, []},
            {:delete, elsewhere.id, 404, :not_found, []},
            {:delete, "not-a-uuid", 400, :invalid_parameter, malformed},
            {:put, "not-a-uuid", 400, :invalid_parameter, malformed}
          ],
          do: {caller, verb, project.id, id, status, code, entries}

    held_elsewhere =
      for caller <- people,
          do: {caller, :put, project.id, elsewhere.id, 409, :id_taken, []}

    unknown_project =
      for {caller, status, code} <- [
            {session_conn(conn, owner), 403, :forbidden},
            {session_conn(conn, superuser), 404, :not_found},
            {service_account, 404, :not_found}
          ],
          verb <- [:put, :delete],
          do: {caller, verb, Ecto.UUID.generate(), kept.id, status, code, []}

    for {caller, verb, project_id, id, status, code, entries} <-
          refused ++ permitted ++ held_elsewhere ++ unknown_project do
      caller
      |> reach(verb, project_id, id)
      |> assert_problem(status, code, entries)
    end

    for keychain <- [kept, kept_mfa, elsewhere] do
      assert Map.take(Repo.get!(KeychainCredential, keychain.id), [
               :name,
               :project_id
             ]) == Map.take(keychain, [:name, :project_id])
    end
  end

  test "an owner of a project scheduled for deletion gets 409 writing or deleting",
       %{conn: conn} do
    owner = insert(:user)

    project =
      insert(:project,
        project_users: [%{user: owner, role: :owner}],
        scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    keychain = insert(:keychain_credential, project: project)

    for verb <- [:put, :delete] do
      conn
      |> session_conn(owner)
      |> reach(verb, project.id, keychain.id)
      |> assert_problem(409, :scheduled_for_deletion, [])
    end

    assert Repo.get(KeychainCredential, keychain.id)
  end
end
