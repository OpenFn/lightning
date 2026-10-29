defmodule LightningWeb.API.Credentials.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiCredentialsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "who may reach it" do
    test "a caller who may not read, replace or delete a credential gets the same 403 for it, an unknown id and a malformed one, and nothing is written",
         %{conn: conn} do
      owner = insert(:user)
      viewer = insert(:user)
      unmet_mfa = insert(:user)

      linked =
        insert(:project, project_users: [%{user: viewer, role: :viewer}])

      requires_mfa =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: unmet_mfa, role: :admin}]
        )

      credential = existing_credential(owner, linked)
      insert(:project_credential, credential: credential, project: requires_mfa)

      scheduled =
        scheduled_for_deletion(
          existing_credential(insert(:user), insert(:project))
        )

      stranger = with_pat(conn, insert(:user))
      superuser = with_pat(conn, insert(:user, role: :superuser))
      viewer = with_pat(conn, viewer)
      unmet_mfa = with_pat(conn, unmet_mfa)
      owner = with_pat(conn, owner)
      unknown = Ecto.UUID.generate()

      for {caller, verb, id} <- [
            {stranger, :get, credential.id},
            {stranger, :get, unknown},
            {stranger, :get, "not-a-uuid"},
            {stranger, :delete, credential.id},
            {stranger, :delete, unknown},
            {stranger, :delete, "not-a-uuid"},
            {stranger, :put, credential.id},
            {stranger, :put, scheduled.id},
            {superuser, :get, credential.id},
            {superuser, :get, unknown},
            {superuser, :get, "not-a-uuid"},
            {superuser, :delete, credential.id},
            {superuser, :delete, unknown},
            {superuser, :delete, "not-a-uuid"},
            {superuser, :put, credential.id},
            {superuser, :put, scheduled.id},
            {unmet_mfa, :get, credential.id},
            {unmet_mfa, :get, unknown},
            {unmet_mfa, :get, "not-a-uuid"},
            {unmet_mfa, :delete, credential.id},
            {unmet_mfa, :delete, unknown},
            {unmet_mfa, :delete, "not-a-uuid"},
            {unmet_mfa, :put, credential.id},
            {unmet_mfa, :put, scheduled.id},
            {viewer, :put, credential.id},
            {viewer, :put, scheduled.id},
            {viewer, :delete, credential.id},
            {viewer, :delete, unknown},
            {viewer, :delete, "not-a-uuid"},
            {owner, :get, unknown},
            {owner, :get, "not-a-uuid"},
            {owner, :delete, unknown},
            {owner, :delete, "not-a-uuid"}
          ] do
        caller |> reach(verb, id) |> assert_problem(403, :forbidden, [])
      end

      assert %Credential{name: "Acme DHIS2"} = Repo.reload!(credential)
      assert %Credential{name: "Acme DHIS2"} = Repo.reload!(scheduled)
      assert main_body(credential.id) == %{"password" => "old"}
      refute Repo.get(Credential, unknown)
    end

    test "only the service account learns that an id names no credential, or isn't a UUID, on GET, and nobody on DELETE; anyone holding the grant gets 400 for a malformed id on PUT",
         %{conn: conn} do
      {service_account, _account} =
        with_service_account(conn, ["credentials:write"])

      person = with_pat(conn, insert(:user))

      for {caller, verb, id, status, code, entries} <- [
            {service_account, :get, Ecto.UUID.generate(), 404, :not_found, []},
            {service_account, :get, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(%{"path" => "id"})]},
            {service_account, :delete, Ecto.UUID.generate(), 403, :forbidden,
             []},
            {service_account, :delete, "not-a-uuid", 403, :forbidden, []},
            {service_account, :put, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(%{"path" => "id"})]},
            {person, :put, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(%{"path" => "id"})]}
          ] do
        caller |> reach(verb, id) |> assert_problem(status, code, entries)
      end
    end
  end

  describe "who may list a project's credentials" do
    test "a caller without standing or MFA gets the same 403 for a project, an unknown id and a malformed one; only a caller who may learn which projects exist hears 404 or 400",
         %{conn: conn} do
      unmet_mfa = insert(:user)

      project =
        insert(:project, project_users: [%{user: insert(:user), role: :owner}])

      requires_mfa =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: unmet_mfa, role: :admin}]
        )

      {service_account, _account} =
        with_service_account(conn, ["credentials:write"])

      stranger = with_pat(conn, insert(:user))
      superuser = with_pat(conn, insert(:user, role: :superuser))
      unmet_mfa = with_pat(conn, unmet_mfa)
      unknown = Ecto.UUID.generate()

      for {route, location} <- [
            list: %{"parameter" => "project_id"},
            nested: %{"path" => "project_id"}
          ],
          {caller, project_id, status, code, entries} <- [
            {stranger, project.id, 403, :forbidden, []},
            {stranger, unknown, 403, :forbidden, []},
            {stranger, "not-a-uuid", 403, :forbidden, []},
            {unmet_mfa, requires_mfa.id, 403, :forbidden, []},
            {unmet_mfa, unknown, 403, :forbidden, []},
            {unmet_mfa, "not-a-uuid", 403, :forbidden, []},
            {superuser, project.id, 403, :forbidden, []},
            {superuser, unknown, 404, :not_found, []},
            {superuser, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(location)]},
            {service_account, unknown, 404, :not_found, []},
            {service_account, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(location)]}
          ] do
        caller
        |> reach(route, project_id)
        |> assert_problem(status, code, entries)
      end

      for {caller, status, code, entries} <- [
            {stranger, 403, :forbidden, []},
            {superuser, 400, :invalid_parameter,
             [not_a_uuid_entry(%{"parameter" => "project_id"})]},
            {service_account, 400, :invalid_parameter,
             [not_a_uuid_entry(%{"parameter" => "project_id"})]}
          ] do
        caller
        |> reach(:list, %{"a" => "x"})
        |> assert_problem(status, code, entries)
      end
    end
  end

  defp reach(conn, :get, id), do: get(conn, ~p"/api/credentials/#{id}")

  defp reach(conn, :list, project_id),
    do: get(conn, ~p"/api/credentials?#{%{project_id: project_id}}")

  defp reach(conn, :nested, project_id),
    do: get(conn, ~p"/api/projects/#{project_id}/credentials")

  defp reach(conn, :delete, id), do: delete(conn, ~p"/api/credentials/#{id}")

  # A body no route would accept, so a refusal that comes first is visible.
  defp reach(conn, :put, id),
    do: put_credential(conn, id, credential_body(%{"nonsense" => 1}))
end
