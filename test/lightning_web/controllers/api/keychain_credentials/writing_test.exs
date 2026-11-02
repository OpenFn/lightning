defmodule LightningWeb.API.KeychainCredentials.WritingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiKeychainHelpers
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Repo

  defp owner_and_project(_context) do
    owner = insert(:user)
    project = insert(:project, project_users: [%{user: owner, role: :owner}])
    credential = insert(:credential, name: "Acme DHIS2", user: owner)
    insert(:project_credential, project: project, credential: credential)
    %{owner: owner, project: project, credential: credential}
  end

  defp entry(pointer, code, detail),
    do: %{"pointer" => pointer, "code" => code, "detail" => detail}

  defp loaded(id),
    do:
      KeychainCredential
      |> Repo.get!(id)
      |> Repo.preload([:created_by, :default_credential])

  describe "creating and replacing" do
    setup :owner_and_project

    test "an owner on Lightning's own app creates one under the path id, recorded as its creator",
         %{conn: conn, owner: owner, project: project, credential: credential} do
      id = Ecto.UUID.generate()

      conn =
        conn
        |> session_conn(owner)
        |> put_keychain(project.id, id, %{
          "name" => "Per-district",
          "path" => "$.district",
          "default_credential_id" => credential.id
        })

      keychain = loaded(id)
      assert json_response(conn, 201) == %{"data" => keychain_json(keychain)}

      assert %{
               name: "Per-district",
               path: "$.district",
               created_by_id: created_by_id,
               default_credential_id: default_id
             } = keychain

      assert created_by_id == owner.id and default_id == credential.id

      assert json_response(conn, 201)["data"]["created_by"]["email"] ==
               owner.email
    end

    test "replaces the name, path and default credential, clearing a default left out",
         %{conn: conn, owner: owner, project: project, credential: credential} do
      creator = insert(:user)

      keychain =
        insert(:keychain_credential,
          project: project,
          created_by: creator,
          default_credential: credential
        )

      conn =
        conn
        |> session_conn(owner)
        |> put_keychain(project.id, keychain.id, %{
          "name" => "renamed",
          "path" => "$.facility"
        })

      replaced = loaded(keychain.id)
      assert json_response(conn, 200) == %{"data" => keychain_json(replaced)}

      assert %{name: "renamed", path: "$.facility", default_credential_id: nil} =
               replaced

      assert replaced.created_by_id == creator.id
    end

    test "a service account with credentials:write replaces one", %{
      conn: conn,
      project: project
    } do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      keychain = insert(:keychain_credential, project: project)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_keychain(project.id, keychain.id, %{
          "name" => "renamed",
          "path" => "$.x"
        })

      assert json_response(conn, 200)["data"]["name"] == "renamed"
    end

    test "a service account may not create one, since it isn't a person who could have created it",
         %{conn: conn, project: project} do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      elsewhere = insert(:keychain_credential)

      for id <- [Ecto.UUID.generate(), elsewhere.id] do
        conn
        |> put_req_header("accept", "application/json")
        |> put_keychain(project.id, id, %{"name" => "new", "path" => "$.x"})
        |> assert_problem(403, :forbidden, [])
      end

      assert Repo.aggregate(
               from(k in KeychainCredential, where: k.project_id == ^project.id),
               :count
             ) == 0
    end
  end

  describe "refusing a body" do
    setup :owner_and_project

    test "refuses a body it cannot take with one 422, each error at its key",
         %{conn: conn, owner: owner, project: project} do
      outside = insert(:credential, user: owner)
      conn = session_conn(conn, owner)

      for {body, entries} <- [
            {%{},
             [
               entry("#/name", "required", "can't be blank"),
               entry("#/path", "required", "can't be blank")
             ]},
            {%{"name" => "k", "path" => "district"},
             [entry("#/path", "format", "JSONPath must start with '$'")]},
            {%{"name" => String.duplicate("n", 256), "path" => "$.x"},
             [
               entry(
                 "#/name",
                 "too_long",
                 "should be at most 255 character(s)"
               )
             ]},
            {%{
               "name" => "k",
               "path" => "$.x",
               "default_credential_id" => outside.id
             },
             [
               entry(
                 "#/default_credential_id",
                 "not_found",
                 "must belong to the same project"
               )
             ]},
            {%{
               "name" => "k",
               "path" => "$.x",
               "colour" => "red",
               "id" => Ecto.UUID.generate()
             },
             [
               entry("#/colour", "unknown_key", "is not accepted"),
               entry("#/id", "mismatch", "does not match the id in the path")
             ]}
          ] do
        id = Ecto.UUID.generate()

        conn
        |> put_keychain(project.id, id, body)
        |> assert_problem(422, :invalid, entries)

        refute Repo.get(KeychainCredential, id)
      end
    end

    test "answers 422 with a taken entry for a name another of the project's keychain credentials has",
         %{conn: conn, owner: owner, project: project} do
      insert(:keychain_credential, project: project, name: "taken")
      id = Ecto.UUID.generate()

      conn
      |> session_conn(owner)
      |> put_keychain(project.id, id, %{"name" => "taken", "path" => "$.x"})
      |> assert_problem(422, :invalid, [
        entry("#/name", "taken", "has already been taken")
      ])

      refute Repo.get(KeychainCredential, id)
    end

    test "answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      owner: owner,
      project: project
    } do
      conn
      |> session_conn(owner)
      |> put_keychain(project.id, Ecto.UUID.generate(), ["k"])
      |> assert_problem(400, :malformed, [])
    end
  end

  describe "deleting" do
    setup :owner_and_project

    test "an owner on Lightning's own app deletes one, and jobs that used it are left without it",
         %{conn: conn, owner: owner, project: project} do
      keychain = insert(:keychain_credential, project: project)
      workflow = insert(:simple_workflow, project: project)

      job =
        workflow.jobs
        |> hd()
        |> Ecto.Changeset.change(keychain_credential_id: keychain.id)
        |> Repo.update!()

      conn =
        conn
        |> session_conn(owner)
        |> delete_keychain(project.id, keychain.id)

      assert response(conn, 204) == ""
      refute Repo.get(KeychainCredential, keychain.id)
      assert Repo.reload!(job).keychain_credential_id == nil
    end

    test "a service account with credentials:write deletes one", %{
      conn: conn,
      project: project
    } do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      keychain = insert(:keychain_credential, project: project)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> delete_keychain(project.id, keychain.id)

      assert response(conn, 204) == ""
      refute Repo.get(KeychainCredential, keychain.id)
    end
  end

  describe "stale writes" do
    setup :owner_and_project

    test "a keychain credential another request deletes mid-replace answers 409 concurrent_edit",
         %{conn: conn, owner: owner, project: project} do
      keychain = insert(:keychain_credential, project: project)

      after_first_query("keychain_credentials", keychain.id, fn id ->
        Repo.query!("DELETE FROM keychain_credentials WHERE id = $1", [id])
      end)

      conn
      |> session_conn(owner)
      |> put_keychain(project.id, keychain.id, %{"name" => "x", "path" => "$.x"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.get(KeychainCredential, keychain.id)
    end

    test "a keychain credential another request deletes mid-delete answers 409 concurrent_edit",
         %{conn: conn, owner: owner, project: project} do
      keychain = insert(:keychain_credential, project: project)

      after_first_query("keychain_credentials", keychain.id, fn id ->
        Repo.query!("DELETE FROM keychain_credentials WHERE id = $1", [id])
      end)

      conn
      |> session_conn(owner)
      |> delete_keychain(project.id, keychain.id)
      |> assert_problem(409, :concurrent_edit, [])
    end
  end
end
