defmodule LightningWeb.API.Credentials.TransferTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.RaceHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiCredentialsHelpers
  import Swoosh.TestAssertions

  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp start(conn, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/credentials/#{id}/transfer", Jason.encode!(body))
  end

  defp cancel(conn, id), do: delete(conn, ~p"/api/credentials/#{id}/transfer")

  # A credential linked to a project its owner and the recipient share.
  defp shared(owner, recipient) do
    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: recipient, role: :viewer}
        ]
      )

    existing_credential(owner, project)
  end

  defp pending(credential) do
    credential
    |> Ecto.Changeset.change(transfer_status: :pending)
    |> Repo.update!()
  end

  describe "starting" do
    test "the owner starts a transfer, Lightning emails them a link, and it answers 200 with the credential pending",
         %{conn: conn} do
      owner = insert(:user)
      recipient = insert(:user, first_name: "Grace")
      credential = shared(owner, recipient)

      conn =
        conn
        |> with_pat(owner)
        |> start(credential.id, %{"recipient" => recipient.email})

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert %Credential{transfer_status: :pending, user_id: owner_id} =
               Repo.reload!(credential)

      assert owner_id == owner.id

      assert_email_sent(
        subject: "Transfer Acme DHIS2 to Grace",
        to: Swoosh.Email.Recipient.format(owner)
      )
    end

    test "a session token starts the owner's transfer, matching the email in any case" do
      owner = insert(:user)
      recipient = insert(:user)
      credential = shared(owner, recipient)

      conn =
        build_conn()
        |> session_conn(owner)
        |> start(credential.id, %{"recipient" => String.upcase(recipient.email)})

      assert json_response(conn, 200)["credential"]["transfer_status"] ==
               "pending"
    end

    test "an unknown email, a recipient missing from a linked project, yourself, a missing or odd recipient and unknown keys are refused, starting nothing",
         %{conn: conn} do
      owner = insert(:user)
      outsider = insert(:user)
      credential = shared(owner, insert(:user))
      conn = with_pat(conn, owner)

      for {body, entries} <- [
            {%{"recipient" => "nobody@example.com"},
             [entry("not_found", "User does not exist")]},
            {%{"recipient" => outsider.email},
             [
               entry(
                 "no_access",
                 "is not a member of every project the credential is linked to"
               )
             ]},
            {%{"recipient" => owner.email},
             [
               entry(
                 "not_allowed",
                 "You cannot transfer a credential to yourself"
               )
             ]},
            {%{"recipient" => "not an email"},
             [entry("format", "must be a valid email address")]},
            {%{"note" => "hi"},
             [
               entry("required", "can't be blank"),
               %{
                 "pointer" => "#/note",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]},
            {%{"recipient" => 1}, [entry("type", "must be an email")]}
          ] do
        conn
        |> start(credential.id, body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Repo.reload!(credential).transfer_status == nil
      refute_email_sent()
    end

    test "an instance that doesn't allow transfers answers 501 not_implemented",
         %{conn: conn} do
      Mox.stub(Lightning.MockConfig, :allow_credential_transfer?, fn -> false end)

      owner = insert(:user)
      recipient = insert(:user)
      credential = shared(owner, recipient)

      conn
      |> with_pat(owner)
      |> start(credential.id, %{"recipient" => recipient.email})
      |> assert_problem(501, :not_implemented, [])

      assert Repo.reload!(credential).transfer_status == nil
    end
  end

  describe "cancelling" do
    test "the owner cancels a pending transfer, answering 200 with the credential",
         %{conn: conn} do
      owner = insert(:user)
      credential = pending(shared(owner, insert(:user)))

      conn = conn |> with_pat(owner) |> cancel(credential.id)

      assert json_response(conn, 200) == %{
               "credential" => credential_json(credential),
               "errors" => %{}
             }

      assert Repo.reload!(credential).transfer_status == nil
    end

    test "a session token cancels the owner's pending transfer" do
      owner = insert(:user)
      credential = pending(shared(owner, insert(:user)))

      build_conn()
      |> session_conn(owner)
      |> cancel(credential.id)
      |> json_response(200)

      assert Repo.reload!(credential).transfer_status == nil
    end

    test "a credential with no pending transfer answers 404 not_found", %{
      conn: conn
    } do
      owner = insert(:user)
      credential = shared(owner, insert(:user))

      conn
      |> with_pat(owner)
      |> cancel(credential.id)
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "stale writes" do
    test "a credential another request deletes mid-start answers 409 concurrent_edit, emailing nobody",
         %{conn: conn} do
      owner = insert(:user)
      recipient = insert(:user)
      credential = shared(owner, recipient)
      delete_mid_write("project_credentials", credential)

      conn
      |> with_pat(owner)
      |> start(credential.id, %{"recipient" => recipient.email})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
      refute_email_sent()
    end

    test "a credential another request deletes mid-cancel answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      credential = pending(shared(owner, insert(:user)))
      delete_mid_write("credentials", credential)

      conn
      |> with_pat(owner)
      |> cancel(credential.id)
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
    end
  end

  describe "who may reach it" do
    test "anyone but the owner gets the same 403 for a credential, an unknown id and a malformed one, and so does the owner for the last two",
         %{conn: conn} do
      owner = insert(:user)
      recipient = insert(:user)
      admin = insert(:user)
      credential = pending(shared(owner, recipient))

      insert(:project_user,
        project: hd(Repo.preload(credential, :projects).projects),
        user: admin,
        role: :admin
      )

      callers = [
        with_pat(conn, insert(:user)),
        with_pat(conn, insert(:user, role: :superuser)),
        with_pat(conn, admin),
        with_pat(conn, recipient)
      ]

      rows =
        for caller <- callers,
            id <- [credential.id, Ecto.UUID.generate(), "not-a-uuid"],
            verb <- [:start, :cancel],
            do: {caller, verb, id}

      owner_rows =
        for id <- [Ecto.UUID.generate(), "not-a-uuid"],
            verb <- [:start, :cancel],
            do: {with_pat(conn, owner), verb, id}

      for {caller, verb, id} <- rows ++ owner_rows do
        caller
        |> reach(verb, id, recipient)
        |> assert_problem(403, :forbidden, [])
      end

      assert Repo.reload!(credential).transfer_status == :pending
      refute_email_sent()
    end

    test "a credential scheduled for deletion answers 409 to its owner", %{
      conn: conn
    } do
      owner = insert(:user)
      recipient = insert(:user)

      credential =
        insert(:credential, name: "Scheduled", schema: "raw", user: owner)
        |> pending()
        |> scheduled_for_deletion()

      for verb <- [:start, :cancel] do
        conn
        |> with_pat(owner)
        |> reach(verb, credential.id, recipient)
        |> assert_problem(409, :scheduled_for_deletion, [])
      end

      assert Repo.reload!(credential).transfer_status == :pending
    end
  end

  defp reach(conn, :start, id, recipient),
    do: start(conn, id, %{"recipient" => recipient.email})

  defp reach(conn, :cancel, id, _recipient), do: cancel(conn, id)

  defp entry(code, detail),
    do: %{"pointer" => "#/recipient", "code" => code, "detail" => detail}

  defp delete_mid_write(table, credential) do
    after_first_query(table, credential.id, fn id ->
      for child <- ~w(credential_bodies project_credentials) do
        Repo.query!("DELETE FROM #{child} WHERE credential_id = $1", [id])
      end

      Repo.query!("DELETE FROM credentials WHERE id = $1", [id])
    end)
  end
end
