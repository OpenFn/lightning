defmodule LightningWeb.API.Credentials.ProjectLinksTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiCredentialsHelpers

  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp link(conn, project_id, id),
    do: put(conn, ~p"/api/projects/#{project_id}/credentials/#{id}")

  defp unlink(conn, project_id, id),
    do: delete(conn, ~p"/api/projects/#{project_id}/credentials/#{id}")

  defp linked_project_ids_of(credential) do
    Repo.all(
      from pc in ProjectCredential,
        where: pc.credential_id == ^credential.id,
        select: pc.project_id,
        order_by: pc.project_id
    )
  end

  defp unlinked_credential(owner) do
    insert(:credential, name: "Unlinked", schema: "raw", user: owner)
    |> with_body(%{name: "main", body: %{"password" => "old"}})
  end

  defp events(credential, event) do
    Repo.all(
      from a in Lightning.Credentials.Audit.base_query(),
        where: a.item_id == ^credential.id and a.event == ^event,
        select: a.changes
    )
  end

  describe "linking" do
    test "the owner, an editor there, links the credential to the project and its sandboxes, answering 201 with the credential",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :editor}])
      sandbox = insert(:project, parent: project)
      credential = unlinked_credential(owner)

      conn = conn |> with_pat(owner) |> link(project.id, credential.id)

      assert json_response(conn, 201) == %{
               "credential" =>
                 credential
                 |> credential_json()
                 |> Map.update!(
                   "project_credentials",
                   &Enum.filter(&1, fn l -> l["project_id"] == project.id end)
                 )
                 |> Map.update!(
                   "projects",
                   &Enum.filter(&1, fn p -> p["id"] == project.id end)
                 ),
               "errors" => %{}
             }

      assert linked_project_ids_of(credential) ==
               Enum.sort([project.id, sandbox.id])

      assert [%{after: %{"project_id" => project_id}}] =
               events(credential, "added_to_project")

      assert project_id == project.id
    end

    test "a session token links the owner's credential" do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      credential = unlinked_credential(owner)

      build_conn()
      |> session_conn(owner)
      |> link(project.id, credential.id)
      |> json_response(201)

      assert linked_project_ids_of(credential) == [project.id]
    end

    test "the service account links anyone's credential to a project its owner is a member of",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :viewer}])
      credential = unlinked_credential(owner)

      {conn, _account} =
        with_service_account(conn, ["credentials:write", "projects:write"])

      conn = link(conn, project.id, credential.id)

      assert json_response(conn, 201) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert linked_project_ids_of(credential) == [project.id]
    end

    test "linking a credential already linked answers 200 and writes nothing",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      credential = existing_credential(owner, project)
      audits = audit_ids(credential.id)

      conn = conn |> with_pat(owner) |> link(project.id, credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert audit_ids(credential.id) == audits
    end

    test "an owner who isn't a member is refused at the path's project_id, and an external_id clash at the path's id",
         %{conn: conn} do
      owner = insert(:user)

      member_project =
        insert(:project, project_users: [%{user: owner, role: :owner}])

      outside_project = insert(:project)

      credential =
        insert(:credential,
          name: "Ext",
          schema: "raw",
          user: owner,
          external_id: "acme"
        )

      insert(:credential,
        name: "Other",
        user: insert(:user),
        external_id: "acme",
        project_credentials: [%{project_id: member_project.id}]
      )

      {service_account, _} = with_service_account(conn, ["credentials:write"])

      service_account
      |> link(outside_project.id, credential.id)
      |> assert_problem(422, :invalid, [
        %{
          "path" => "project_id",
          "code" => "no_access",
          "detail" => "the credential's owner is not a member of this project"
        }
      ])

      service_account
      |> link(member_project.id, credential.id)
      |> assert_problem(422, :invalid, [
        %{
          "path" => "id",
          "code" => "taken",
          "detail" =>
            "another credential with the same external ID already exists in this project"
        }
      ])

      assert linked_project_ids_of(credential) == []
    end

    test "a body with keys is refused 422 unknown_key, linking nothing", %{
      conn: conn
    } do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      credential = unlinked_credential(owner)

      conn
      |> with_pat(owner)
      |> put_req_header("content-type", "application/json")
      |> put(
        ~p"/api/projects/#{project.id}/credentials/#{credential.id}",
        Jason.encode!(%{"role" => "x"})
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/role",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ])

      assert linked_project_ids_of(credential) == []
    end
  end

  describe "unlinking" do
    test "the owner unlinks the credential, answering 204; jobs in the project lose it, sandbox links stay",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :viewer}])
      sandbox = insert(:project, parent: project)
      credential = existing_credential(owner, project)
      insert(:project_credential, credential: credential, project: sandbox)

      [link] =
        Repo.all(
          from pc in ProjectCredential,
            where:
              pc.credential_id == ^credential.id and pc.project_id == ^project.id
        )

      job = insert(:job, project_credential: link)

      conn = conn |> with_pat(owner) |> unlink(project.id, credential.id)

      assert response(conn, 204) == ""
      assert linked_project_ids_of(credential) == [sandbox.id]
      assert Repo.reload!(job).project_credential_id == nil

      assert [%{before: %{"project_id" => project_id}}] =
               events(credential, "removed_from_project")

      assert project_id == project.id
    end

    test "a project owner or admin unlinks someone else's credential, with a personal access token or a session token",
         %{conn: conn} do
      [project_owner, admin, owner] = insert_list(3, :user)

      project =
        insert(:project,
          project_users: [
            %{user: project_owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: owner, role: :editor}
          ]
        )

      first = existing_credential(owner, project)
      second = unlinked_credential(owner)
      insert(:project_credential, credential: second, project: project)

      conn
      |> with_pat(project_owner)
      |> unlink(project.id, first.id)
      |> response(204)

      build_conn()
      |> session_conn(admin)
      |> unlink(project.id, second.id)
      |> response(204)

      assert linked_project_ids_of(first) == []
      assert linked_project_ids_of(second) == []
    end

    test "the service account unlinks anyone's credential", %{conn: conn} do
      project = insert(:project)
      credential = existing_credential(insert(:user), project)
      {conn, _account} = with_service_account(conn, ["credentials:write"])

      conn |> unlink(project.id, credential.id) |> response(204)

      assert linked_project_ids_of(credential) == []
    end
  end

  describe "stale writes" do
    test "a credential another request deletes mid-link answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      credential = unlinked_credential(owner)

      after_first_query("credentials", credential.id, fn id ->
        Repo.query!("DELETE FROM credential_bodies WHERE credential_id = $1", [
          id
        ])

        Repo.query!("DELETE FROM credentials WHERE id = $1", [id])
      end)

      conn
      |> with_pat(owner)
      |> link(project.id, credential.id)
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
      refute Repo.get_by(ProjectCredential, project_id: project.id)
    end

    test "a credential another request links mid-link answers 200 as already linked, adding no second link",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      credential = unlinked_credential(owner)

      after_first_query("project_credentials", credential.id, fn _id ->
        insert(:project_credential, project: project, credential: credential)
      end)

      conn = conn |> with_pat(owner) |> link(project.id, credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert linked_project_ids_of(credential) == [project.id]
      assert events(credential, "added_to_project") == []
    end

    test "a link another request removes mid-unlink answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      credential = existing_credential(owner, project)

      after_first_query("project_credentials", credential.id, fn id ->
        Repo.query!("DELETE FROM project_credentials WHERE credential_id = $1", [
          id
        ])
      end)

      conn
      |> with_pat(owner)
      |> unlink(project.id, credential.id)
      |> assert_problem(409, :concurrent_edit, [])

      assert linked_project_ids_of(credential) == []
      assert events(credential, "removed_from_project") == []
    end
  end

  describe "who may reach it" do
    setup do
      owner = insert(:user)
      [viewer, editor, unmet_mfa, stranger] = insert_list(4, :user)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :editor},
            %{user: viewer, role: :viewer},
            %{user: editor, role: :editor}
          ]
        )

      requires_mfa =
        insert(:project,
          requires_mfa: true,
          project_users: [
            %{user: unmet_mfa, role: :owner},
            %{user: owner, role: :admin}
          ]
        )

      %{
        owner: owner,
        viewer: viewer,
        editor: editor,
        unmet_mfa: unmet_mfa,
        stranger: stranger,
        project: project,
        requires_mfa: requires_mfa,
        linked: existing_credential(owner, project),
        unlinked: unlinked_credential(owner)
      }
    end

    test "a caller without standing, a role the rule refuses or MFA gets the same 403 for the project, an unknown id and a malformed one",
         %{conn: conn} = ctx do
      unknown = Ecto.UUID.generate()
      stranger = with_pat(conn, ctx.stranger)
      viewer = with_pat(conn, ctx.viewer)
      unmet_mfa = with_pat(conn, ctx.unmet_mfa)
      superuser = with_pat(conn, insert(:user, role: :superuser))

      rows =
        for project_id <- [ctx.project.id, unknown, "not-a-uuid"],
            verb <- [:link, :unlink],
            do: {stranger, verb, project_id, ctx.linked.id}

      rows =
        rows ++
          for verb <- [:link, :unlink],
              do: {superuser, verb, ctx.project.id, ctx.linked.id}

      rows =
        rows ++
          for {project_id, id} <- [
                {ctx.requires_mfa.id, ctx.unlinked.id},
                {ctx.requires_mfa.id, unknown},
                {ctx.requires_mfa.id, "not-a-uuid"}
              ],
              verb <- [:link, :unlink],
              do: {unmet_mfa, verb, project_id, id}

      # A viewer may not link at all, so the credential's id doesn't matter.
      rows =
        rows ++
          for id <- [ctx.unlinked.id, unknown, "not-a-uuid"],
              do: {viewer, :link, ctx.project.id, id}

      for {caller, verb, project_id, id} <- rows do
        caller
        |> reach(verb, project_id, id)
        |> assert_problem(403, :forbidden, [])
      end

      # A superuser may learn which projects exist.
      for verb <- [:link, :unlink] do
        superuser
        |> reach(verb, unknown, ctx.linked.id)
        |> assert_problem(404, :not_found, [])

        superuser
        |> reach(verb, "not-a-uuid", ctx.linked.id)
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "project_id"})
        ])
      end

      assert linked_project_ids_of(ctx.linked) == [ctx.project.id]
      assert linked_project_ids_of(ctx.unlinked) == []
    end

    test "linking: an editor who doesn't own the credential gets 403 for it, an unknown id and a malformed one; only the service account hears 404 and 400",
         %{conn: conn} = ctx do
      editor = with_pat(conn, ctx.editor)
      owner = with_pat(conn, ctx.owner)
      {service_account, _} = with_service_account(conn, ["credentials:write"])

      for {caller, id, status, code, entries} <- [
            {editor, ctx.unlinked.id, 403, :forbidden, []},
            {editor, ctx.linked.id, 403, :forbidden, []},
            {editor, Ecto.UUID.generate(), 403, :forbidden, []},
            {editor, "not-a-uuid", 403, :forbidden, []},
            {owner, Ecto.UUID.generate(), 403, :forbidden, []},
            {owner, "not-a-uuid", 403, :forbidden, []},
            {service_account, Ecto.UUID.generate(), 404, :not_found, []},
            {service_account, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(%{"path" => "id"})]}
          ] do
        caller
        |> reach(:link, ctx.project.id, id)
        |> assert_problem(status, code, entries)
      end

      for {caller, project_id, status, code, entries} <- [
            {service_account, Ecto.UUID.generate(), 404, :not_found, []},
            {service_account, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(%{"path" => "project_id"})]}
          ] do
        caller
        |> reach(:link, project_id, ctx.unlinked.id)
        |> assert_problem(status, code, entries)
      end

      assert linked_project_ids_of(ctx.unlinked) == []
    end

    test "unlinking: anyone in the project hears 404 for a credential that isn't linked and 400 for a malformed id, and a viewer or editor who doesn't own it gets 403",
         %{conn: conn} = ctx do
      viewer = with_pat(conn, ctx.viewer)
      editor = with_pat(conn, ctx.editor)

      for {caller, id, status, code, entries} <- [
            {viewer, ctx.linked.id, 403, :forbidden, []},
            {editor, ctx.linked.id, 403, :forbidden, []},
            {viewer, ctx.unlinked.id, 404, :not_found, []},
            {viewer, Ecto.UUID.generate(), 404, :not_found, []},
            {viewer, "not-a-uuid", 400, :invalid_parameter,
             [not_a_uuid_entry(%{"path" => "id"})]}
          ] do
        caller
        |> reach(:unlink, ctx.project.id, id)
        |> assert_problem(status, code, entries)
      end

      assert linked_project_ids_of(ctx.linked) == [ctx.project.id]
    end

    test "a project scheduled for deletion answers 409 to a caller permitted there",
         %{conn: conn} = ctx do
      project =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.add(7, :day),
          project_users: [%{user: ctx.owner, role: :owner}]
        )

      owner = with_pat(conn, ctx.owner)

      for {verb, id} <- [link: ctx.unlinked.id, unlink: Ecto.UUID.generate()] do
        owner
        |> reach(verb, project.id, id)
        |> assert_problem(409, :scheduled_for_deletion, [])
      end
    end

    test "linking a credential scheduled for deletion answers 409 to its owner",
         %{conn: conn} = ctx do
      scheduled_for_deletion(ctx.unlinked)

      conn
      |> with_pat(ctx.owner)
      |> reach(:link, ctx.project.id, ctx.unlinked.id)
      |> assert_problem(409, :scheduled_for_deletion, [])

      assert linked_project_ids_of(ctx.unlinked) == []
    end
  end

  defp reach(conn, :link, project_id, id), do: link(conn, project_id, id)
  defp reach(conn, :unlink, project_id, id), do: unlink(conn, project_id, id)
end
