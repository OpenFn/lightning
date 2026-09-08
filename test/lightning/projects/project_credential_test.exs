defmodule Lightning.Projects.ProjectCredentialTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.ProjectCredential

  import Lightning.Factories

  describe "the credential-body grant" do
    setup do
      project = insert(:project)

      mine =
        insert(:credential)
        |> with_body(%{name: "main", body: %{"key" => "mine"}})

      theirs =
        insert(:credential)
        |> with_body(%{name: "main", body: %{"key" => "theirs"}})

      %{
        project: project,
        share: insert(:project_credential, project: project, credential: mine),
        my_body: hd(mine.credential_bodies),
        their_body: hd(theirs.credential_bodies),
        mine: mine
      }
    end

    defp set_grant(share, body_id) do
      Repo.query(
        "UPDATE project_credentials SET credential_body_id = $1 WHERE id = $2",
        [dump(body_id), dump(share.id)]
      )
    end

    defp dump(nil), do: nil
    defp dump(uuid), do: Ecto.UUID.dump!(uuid)

    test "a share may grant one of its own credential's bodies", %{
      share: share,
      my_body: my_body
    } do
      assert {:ok, _} = set_grant(share, my_body.id)

      assert Repo.reload!(share).credential_body_id == my_body.id
    end

    test "a share may not grant another credential's body", %{
      share: share,
      their_body: their_body
    } do
      # A single-column reference would allow this, which is the same hole in a
      # new place: the share would read values belonging to a credential it was
      # never given.
      assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
               set_grant(share, their_body.id)
    end

    test "no grant is the default, and means the share resolves nothing", %{
      share: share
    } do
      assert is_nil(share.credential_body_id)
    end

    test "a granted body cannot be deleted out from under the share", %{
      share: share,
      my_body: my_body
    } do
      {:ok, _} = set_grant(share, my_body.id)

      assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
               Repo.query("DELETE FROM credential_bodies WHERE id = $1", [
                 dump(my_body.id)
               ])
    end

    test "deleting the whole credential still works", %{
      share: share,
      my_body: my_body,
      mine: mine
    } do
      {:ok, _} = set_grant(share, my_body.id)

      # The share and the body both cascade from credential_id in one statement,
      # so the grant's constraint has to be checked at the end of it. RESTRICT
      # would check too early and make the credential undeletable.
      assert {:ok, _} =
               Repo.query("DELETE FROM credentials WHERE id = $1", [
                 dump(mine.id)
               ])

      refute Repo.reload(share)
    end
  end

  test "project_id is NOT NULL at the database layer" do
    credential = insert(:credential)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.insert_all(ProjectCredential, [
          %{
            id: Ecto.UUID.generate(),
            project_id: nil,
            credential_id: credential.id,
            inserted_at: now,
            updated_at: now
          }
        ])
      end

    assert %Postgrex.Error{postgres: %{code: :not_null_violation}} = error
  end
end
