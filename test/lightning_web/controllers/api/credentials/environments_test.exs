defmodule LightningWeb.API.Credentials.EnvironmentsTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiCredentialsHelpers

  alias Lightning.Credentials
  alias Lightning.Credentials.CredentialBody
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp list(conn, id), do: get(conn, ~p"/api/credentials/#{id}/environments")

  defp put_environment(conn, id, name, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/credentials/#{id}/environments/#{name}", Jason.encode!(body))
  end

  defp delete_environment(conn, id, name),
    do: delete(conn, ~p"/api/credentials/#{id}/environments/#{name}")

  defp environment_json(credential_id, name) do
    body = Credentials.get_credential_body(credential_id, name)

    %{
      "name" => name,
      "inserted_at" => DateTime.to_iso8601(body.inserted_at),
      "updated_at" => DateTime.to_iso8601(body.updated_at)
    }
  end

  defp names(credential_id),
    do: credential_id |> environment_names() |> Enum.sort()

  defp environment_names(credential_id) do
    Repo.all(
      from b in CredentialBody,
        where: b.credential_id == ^credential_id,
        select: b.name
    )
  end

  describe "listing" do
    test "lists each environment's name and timestamps by name, without its body, to the owner",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      conn = conn |> with_pat(owner) |> list(credential.id)

      assert json_response(conn, 200) == %{
               "data" => [
                 environment_json(credential.id, "main"),
                 environment_json(credential.id, "staging")
               ]
             }

      refute conn.resp_body =~ "staging\":{"
      refute conn.resp_body =~ "password"
    end

    test "a session token lists the owner's environments" do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      conn = build_conn() |> session_conn(owner) |> list(credential.id)

      assert json_response(conn, 200)["data"] |> Enum.map(& &1["name"]) ==
               ["main", "staging"]
    end

    test "the service account lists anyone's environments", %{conn: conn} do
      credential = existing_credential(insert(:user), insert(:project))
      {conn, _account} = with_service_account(conn, ["credentials:write"])

      assert json_response(list(conn, credential.id), 200)["data"]
             |> Enum.map(& &1["name"]) == ["main", "staging"]
    end
  end

  describe "setting" do
    test "creates an environment, answering 201 with it, and leaves the others",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      conn =
        conn
        |> with_pat(owner)
        |> put_environment(credential.id, "prod", %{
          "body" => %{"password" => "prod"}
        })

      assert json_response(conn, 201) == %{
               "data" => environment_json(credential.id, "prod")
             }

      assert names(credential.id) == ["main", "prod", "staging"]

      assert Credentials.get_credential_body(credential.id, "prod").body == %{
               "password" => "prod"
             }

      assert main_body(credential.id) == %{"password" => "old"}
    end

    test "replaces an environment's body, answering 200 with it, and records an audit event",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      audits = audit_ids(credential.id)

      conn =
        conn
        |> with_pat(owner)
        |> put_environment(credential.id, "staging", %{
          "body" => %{"password" => "new"}
        })

      assert json_response(conn, 200) == %{
               "data" => environment_json(credential.id, "staging")
             }

      assert Credentials.get_credential_body(credential.id, "staging").body ==
               %{"password" => "new"}

      assert length(audit_ids(credential.id)) == length(audits) + 1
    end

    test "sending the same body again answers 200 and writes no audit event",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      audits = audit_ids(credential.id)

      conn
      |> with_pat(owner)
      |> put_environment(credential.id, "staging", %{
        "body" => %{"password" => "staging"}
      })
      |> json_response(200)

      assert audit_ids(credential.id) == audits
    end

    test "a session token sets the owner's environment, and the service account anyone's",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      {service_account, _} = with_service_account(conn, ["credentials:write"])

      build_conn()
      |> session_conn(owner)
      |> put_environment(credential.id, "prod", %{"body" => %{"a" => "b"}})
      |> json_response(201)

      service_account
      |> put_environment(credential.id, "dev", %{"body" => %{"a" => "c"}})
      |> json_response(201)

      assert names(credential.id) == ["dev", "main", "prod", "staging"]
    end

    test "a missing or non-object body, an unknown key and a sixth environment are refused together, writing nothing",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      for name <- ~w(a b c),
          do: insert(:credential_body, credential: credential, name: name)

      conn = with_pat(conn, owner)

      for {body, body_entry} <- [
            {%{"extra" => 1},
             %{
               "pointer" => "#/body",
               "code" => "required",
               "detail" => "can't be blank"
             }},
            {%{"extra" => 1, "body" => "x"},
             %{
               "pointer" => "#/body",
               "code" => "type",
               "detail" => "must be an object"
             }}
          ] do
        conn
        |> put_environment(credential.id, "sixth", body)
        |> assert_problem(422, :invalid, [
          body_entry,
          %{
            "pointer" => "#/extra",
            "code" => "unknown_key",
            "detail" => "is not accepted"
          },
          %{
            "path" => "name",
            "code" => "exceeds_limit",
            "detail" => "a credential may have at most 5 environments"
          }
        ])
      end

      conn
      |> put_environment(credential.id, "staging", "[]")
      |> assert_problem(400, :malformed, [])

      assert names(credential.id) == ["a", "b", "c", "main", "staging"]
    end

    test "a name Lightning doesn't accept is refused at the path's name, and too many secrets at the body",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      conn = with_pat(conn, owner)

      conn
      |> put_environment(credential.id, "Not_A_Slug", %{"body" => %{"a" => "b"}})
      |> assert_problem(422, :invalid, [
        %{
          "path" => "name",
          "code" => "format",
          "detail" => "must be a short slug"
        }
      ])

      secrets =
        Map.new(1..(Lightning.Config.max_credential_sensitive_values() + 1), fn
          i -> {"password#{i}", "secret#{i}"}
        end)

      %{"errors" => [entry]} =
        conn
        |> put_environment(credential.id, "staging", %{"body" => secrets})
        |> assert_problem(422, :invalid)

      assert %{"pointer" => "#/body", "code" => "too_many_secrets"} = entry
      assert names(credential.id) == ["main", "staging"]
    end
  end

  describe "deleting" do
    test "deletes the environment, answering 204, and records an audit event",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      audits = audit_ids(credential.id)

      conn =
        conn |> with_pat(owner) |> delete_environment(credential.id, "staging")

      assert response(conn, 204) == ""
      assert names(credential.id) == ["main"]
      assert length(audit_ids(credential.id)) == length(audits) + 1
    end

    test "a session token deletes the owner's environment, and the service account anyone's",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      insert(:credential_body, credential: credential, name: "prod")
      {service_account, _} = with_service_account(conn, ["credentials:write"])

      build_conn()
      |> session_conn(owner)
      |> delete_environment(credential.id, "staging")
      |> response(204)

      service_account
      |> delete_environment(credential.id, "prod")
      |> response(204)

      assert names(credential.id) == ["main"]
    end

    test "an environment the credential doesn't have answers 404, and the last one 422 required",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      conn = with_pat(conn, owner)

      conn
      |> delete_environment(credential.id, "prod")
      |> assert_problem(404, :not_found, [])

      conn |> delete_environment(credential.id, "staging") |> response(204)

      conn
      |> delete_environment(credential.id, "main")
      |> assert_problem(422, :invalid, [
        %{
          "path" => "name",
          "code" => "required",
          "detail" => "a credential needs at least one environment"
        }
      ])

      assert names(credential.id) == ["main"]
    end
  end

  describe "stale writes" do
    test "a credential another request deletes mid-set answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      delete_mid_write("credentials", credential)

      conn
      |> with_pat(owner)
      |> put_environment(credential.id, "prod", %{"body" => %{"a" => "b"}})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
    end

    test "a credential another request deletes mid-delete answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      delete_mid_write("credential_bodies", credential)

      conn
      |> with_pat(owner)
      |> delete_environment(credential.id, "staging")
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(credential)
    end

    test "deleting one of two environments while another request deletes the other refuses the last one 422 required",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      after_first_query("credential_bodies", credential.id, fn id ->
        Repo.query!(
          "DELETE FROM credential_bodies WHERE credential_id = $1 AND name = 'staging'",
          [id]
        )
      end)

      conn
      |> with_pat(owner)
      |> delete_environment(credential.id, "main")
      |> assert_problem(422, :invalid, [
        %{
          "path" => "name",
          "code" => "required",
          "detail" => "a credential needs at least one environment"
        }
      ])

      assert names(credential.id) == ["main"]
    end

    test "creating a fifth environment while another request creates one refuses the sixth 422 exceeds_limit",
         %{conn: conn} do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))

      for name <- ~w(a b),
          do: insert(:credential_body, credential: credential, name: name)

      after_first_query("credential_bodies", credential.id, fn _id ->
        insert(:credential_body, credential: credential, name: "c")
      end)

      conn
      |> with_pat(owner)
      |> put_environment(credential.id, "sixth", %{"body" => %{"a" => "b"}})
      |> assert_problem(422, :invalid, [
        %{
          "path" => "name",
          "code" => "exceeds_limit",
          "detail" => "a credential may have at most 5 environments"
        }
      ])

      assert names(credential.id) == ["a", "b", "c", "main", "staging"]
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
      stranger = with_pat(conn, insert(:user))
      superuser = with_pat(conn, insert(:user, role: :superuser))
      admin = with_pat(conn, admin)
      owner = with_pat(conn, owner)
      unknown = Ecto.UUID.generate()

      rows =
        for caller <- [stranger, superuser, admin],
            id <- [credential.id, unknown, "not-a-uuid"],
            verb <- [:list, :put, :delete],
            do: {caller, verb, id}

      owner_rows =
        for id <- [unknown, "not-a-uuid"],
            verb <- [:list, :put, :delete],
            do: {owner, verb, id}

      for {caller, verb, id} <- rows ++ owner_rows do
        caller |> reach(verb, id) |> assert_problem(403, :forbidden, [])
      end

      assert names(credential.id) == ["main", "staging"]
      assert main_body(credential.id) == %{"password" => "old"}
    end

    test "a credential scheduled for deletion answers 409 to the owner and the service account",
         %{conn: conn} do
      owner = insert(:user)

      credential =
        insert(:credential, name: "Scheduled", schema: "raw", user: owner)
        |> with_body(%{name: "main", body: %{"password" => "old"}})
        |> with_body(%{name: "staging", body: %{"password" => "old"}})
        |> scheduled_for_deletion()

      {service_account, _} = with_service_account(conn, ["credentials:write"])

      for caller <- [with_pat(conn, owner), service_account],
          verb <- [:list, :put, :delete] do
        caller
        |> reach(verb, credential.id)
        |> assert_problem(409, :scheduled_for_deletion, [])
      end

      assert names(credential.id) == ["main", "staging"]
    end

    test "only the service account learns that an id names no credential, or isn't a UUID",
         %{conn: conn} do
      {service_account, _} = with_service_account(conn, ["credentials:write"])

      for verb <- [:list, :put, :delete] do
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

  defp reach(conn, :list, id), do: list(conn, id)

  defp reach(conn, :put, id),
    do: put_environment(conn, id, "staging", %{"body" => %{"a" => "b"}})

  defp reach(conn, :delete, id), do: delete_environment(conn, id, "staging")

  defp delete_mid_write(table, credential) do
    after_first_query(table, credential.id, fn id ->
      for child <- ~w(credential_bodies project_credentials) do
        Repo.query!("DELETE FROM #{child} WHERE credential_id = $1", [id])
      end

      Repo.query!("DELETE FROM credentials WHERE id = $1", [id])
    end)
  end
end
