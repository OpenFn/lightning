defmodule LightningWeb.API.Credentials.ScheduledDeletionTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiCredentialsHelpers
  import Swoosh.TestAssertions

  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp schedule(conn, id),
    do: put(conn, ~p"/api/credentials/#{id}/scheduled_deletion")

  defp cancel(conn, id),
    do: delete(conn, ~p"/api/credentials/#{id}/scheduled_deletion")

  defp linked_with_job(owner) do
    project = insert(:project, project_users: [%{user: owner, role: :owner}])
    credential = existing_credential(owner, project)
    [link] = Repo.preload(credential, :project_credentials).project_credentials
    job = insert(:job, project_credential: link)
    {credential, job}
  end

  describe "scheduling" do
    test "the owner's personal access token unlinks it from every project and its jobs, emails the owner, and answers 200 with the credential",
         %{conn: conn} do
      owner = insert(:user)
      {credential, job} = linked_with_job(owner)

      conn = conn |> with_pat(owner) |> schedule(credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert %Credential{scheduled_deletion: %DateTime{}} =
               Repo.reload!(credential)

      assert credential_json(credential)["project_credentials"] == []
      assert Repo.reload!(job).project_credential_id == nil

      assert_email_sent(
        subject: "Your \"Acme DHIS2\" credential will be deleted",
        to: Swoosh.Email.Recipient.format(owner)
      )
    end

    test "a session token schedules the owner's credential", %{conn: _conn} do
      owner = insert(:user)
      {credential, _job} = linked_with_job(owner)

      conn = build_conn() |> session_conn(owner) |> schedule(credential.id)

      assert json_response(conn, 200)["credential"]["scheduled_deletion"]
      assert Repo.reload!(credential).scheduled_deletion
    end

    test "the service account schedules anyone's credential", %{conn: conn} do
      {credential, _job} = linked_with_job(insert(:user))

      {conn, _account} =
        with_service_account(conn, ["credentials:write", "projects:write"])

      conn = schedule(conn, credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert Repo.reload!(credential).scheduled_deletion
    end

    test "scheduling one already scheduled answers 200 and changes nothing",
         %{conn: conn} do
      owner = insert(:user)

      credential =
        scheduled_credential(owner)

      before = Repo.reload!(credential)
      conn = conn |> with_pat(owner) |> schedule(credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert Repo.reload!(credential) == before
      refute_email_sent()
    end

    test "a body with keys is refused 422 unknown_key, and one that isn't an object 400 malformed, scheduling nothing",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      conn =
        conn
        |> with_pat(owner)
        |> put_req_header("content-type", "application/json")

      conn
      |> put(
        ~p"/api/credentials/#{credential.id}/scheduled_deletion",
        Jason.encode!(%{"at" => "2030-01-01T00:00:00Z"})
      )
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/at",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ])

      conn
      |> put(~p"/api/credentials/#{credential.id}/scheduled_deletion", "[]")
      |> assert_problem(400, :malformed, [])

      refute Repo.reload!(credential).scheduled_deletion
    end
  end

  describe "cancelling" do
    test "the owner's personal access token clears the schedule and answers 200 with the credential, without restoring links",
         %{conn: conn} do
      owner = insert(:user)
      {credential, _job} = linked_with_job(owner)
      conn = with_pat(conn, owner)

      json_response(schedule(conn, credential.id), 200)
      conn = cancel(conn, credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert %Credential{scheduled_deletion: nil} = Repo.reload!(credential)
      assert credential_json(credential)["project_credentials"] == []
    end

    test "a session token cancels the owner's scheduled deletion" do
      owner = insert(:user)

      credential =
        scheduled_credential(owner)

      conn = build_conn() |> session_conn(owner) |> cancel(credential.id)

      assert json_response(conn, 200)["credential"]["scheduled_deletion"] == nil
      refute Repo.reload!(credential).scheduled_deletion
    end

    test "the service account cancels anyone's scheduled deletion", %{
      conn: conn
    } do
      credential =
        scheduled_credential(insert(:user))

      {conn, _account} =
        with_service_account(conn, ["credentials:write", "projects:write"])

      conn = cancel(conn, credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      refute Repo.reload!(credential).scheduled_deletion
    end

    test "a credential that isn't scheduled answers 404 not_found", %{
      conn: conn
    } do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      conn
      |> with_pat(owner)
      |> cancel(credential.id)
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "stale writes" do
    test "a credential another request deletes mid-schedule answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      delete_mid_write(credential)

      conn
      |> with_pat(owner)
      |> schedule(credential.id)
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
      refute_email_sent()
    end

    test "a credential another request deletes mid-cancel answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)

      credential =
        scheduled_credential(owner)

      delete_mid_write(credential)

      conn
      |> with_pat(owner)
      |> cancel(credential.id)
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
    end
  end

  describe "who may reach it" do
    test "anyone but the owner and the service account gets the same 403 for a credential, an unknown id and a malformed one, and nothing changes",
         %{conn: conn} do
      owner = insert(:user)
      admin = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin}
          ]
        )

      credential = existing_credential(owner, project)

      scheduled =
        scheduled_credential(owner)

      stranger = with_pat(conn, insert(:user))
      superuser = with_pat(conn, insert(:user, role: :superuser))
      admin = with_pat(conn, admin)
      owner = with_pat(conn, owner)
      unknown = Ecto.UUID.generate()

      for caller <- [stranger, superuser, admin],
          {verb, id} <- [
            schedule: credential.id,
            schedule: unknown,
            schedule: "not-a-uuid",
            cancel: scheduled.id,
            cancel: unknown,
            cancel: "not-a-uuid"
          ] do
        caller |> reach(verb, id) |> assert_problem(403, :forbidden, [])
      end

      for {verb, id} <- [
            schedule: unknown,
            schedule: "not-a-uuid",
            cancel: unknown,
            cancel: "not-a-uuid"
          ] do
        owner |> reach(verb, id) |> assert_problem(403, :forbidden, [])
      end

      refute Repo.reload!(credential).scheduled_deletion
      assert Repo.reload!(scheduled).scheduled_deletion
    end

    test "only the service account learns that an id names no credential, or isn't a UUID",
         %{conn: conn} do
      {service_account, _account} =
        with_service_account(conn, ["credentials:write", "projects:write"])

      for verb <- [:schedule, :cancel] do
        service_account
        |> reach(verb, Ecto.UUID.generate())
        |> assert_problem(404, :not_found, [])

        service_account
        |> reach(verb, "not-a-uuid")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "id"})
        ])
      end
    end
  end

  # Scheduling unlinks a credential from every project, so a scheduled one has
  # no links.
  defp scheduled_credential(owner) do
    insert(:credential, name: "Scheduled", schema: "raw", user: owner)
    |> with_body(%{name: "main", body: %{"password" => "old"}})
    |> scheduled_for_deletion()
  end

  defp reach(conn, :schedule, id), do: schedule(conn, id)
  defp reach(conn, :cancel, id), do: cancel(conn, id)

  defp delete_mid_write(credential) do
    after_first_query("credentials", credential.id, fn id ->
      for child <- ~w(credential_bodies project_credentials) do
        Repo.query!("DELETE FROM #{child} WHERE credential_id = $1", [id])
      end

      Repo.query!("DELETE FROM credentials WHERE id = $1", [id])
    end)
  end
end
