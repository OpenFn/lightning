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

  describe "who gets a grant, and who does not" do
    test "creating a credential with one body grants it to the project" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      {:ok, credential} =
        Lightning.Credentials.create_credential(
          %{
            "name" => "one-body",
            "schema" => "raw",
            "user_id" => user.id,
            "credential_bodies" => [
              %{"name" => "main", "body" => %{"key" => "value"}}
            ],
            "project_credentials" => [%{"project_id" => project.id}]
          },
          user
        )

      [share] =
        Repo.preload(credential, :project_credentials).project_credentials

      [body] = Repo.preload(credential, :credential_bodies).credential_bodies

      # Nothing to choose, so the credential works where it was created.
      assert share.credential_body_id == body.id
    end

    test "creating one with several bodies grants nothing, because it is a choice" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      {:ok, credential} =
        Lightning.Credentials.create_credential(
          %{
            "name" => "two-bodies",
            "schema" => "raw",
            "user_id" => user.id,
            "credential_bodies" => [
              %{"name" => "main", "body" => %{"key" => "live"}},
              %{"name" => "staging", "body" => %{"key" => "test"}}
            ],
            "project_credentials" => [%{"project_id" => project.id}]
          },
          user
        )

      [share] =
        Repo.preload(credential, :project_credentials).project_credentials

      assert is_nil(share.credential_body_id)
    end

    test "a sandbox clone gets a reference and no grant" do
      user = insert(:user)
      parent = insert(:project, project_users: [%{user: user, role: :owner}])

      credential =
        insert(:credential, user: user)
        |> with_body(%{name: "main", body: %{"key" => "production"}})

      insert(:project_credential, project: parent, credential: credential)

      {:ok, sandbox} =
        Lightning.Projects.Sandboxes.provision(
          parent,
          user,
          %{name: "a-sandbox"}
        )

      [share] =
        Repo.all(
          from(pc in Lightning.Projects.ProjectCredential,
            where: pc.project_id == ^sandbox.id
          )
        )

      # The sandbox can see the credential and read none of its values. This is
      # the whole point: granting the parent's body here is the hole.
      assert share.credential_id == credential.id
      assert is_nil(share.credential_body_id)
    end

    test "editing a credential with several bodies leaves grants alone" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      credential =
        insert(:credential, user: user)
        |> with_body(%{name: "main", body: %{"key" => "live"}})
        |> with_body(%{name: "staging", body: %{"key" => "test"}})

      # Grant the one that is NOT first, so an overwrite is visible rather than
      # landing on the same row by luck.
      staging = Enum.find(credential.credential_bodies, &(&1.name == "staging"))

      share =
        insert(:project_credential, project: project, credential: credential)

      {:ok, _} =
        Repo.query(
          "UPDATE project_credentials SET credential_body_id = $1 WHERE id = $2",
          [Ecto.UUID.dump!(staging.id), Ecto.UUID.dump!(share.id)]
        )

      {:ok, _} =
        Lightning.Credentials.update_credential(
          credential,
          %{
            "name" => "renamed",
            "credential_bodies" => [
              %{"name" => "main", "body" => %{"key" => "changed"}},
              %{"name" => "staging", "body" => %{"key" => "test"}}
            ]
          },
          user
        )

      assert Repo.reload!(share).credential_body_id == staging.id
    end
  end

  describe "grant_body_to_project/4" do
    setup do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      credential =
        insert(:credential, user: owner)
        |> with_body(%{name: "main", body: %{"key" => "live"}})
        |> with_body(%{name: "dev", body: %{"key" => "test"}})

      bodies = Map.new(credential.credential_bodies, &{&1.name, &1.id})

      share =
        insert(:project_credential, project: project, credential: credential)

      %{
        owner: owner,
        project: project,
        credential: credential,
        bodies: bodies,
        share: share
      }
    end

    test "points the share at a body of that credential", ctx do
      {:ok, _} =
        Lightning.Credentials.grant_body_to_project(
          ctx.project,
          ctx.credential.id,
          ctx.bodies["dev"],
          ctx.owner
        )

      assert Repo.reload!(ctx.share).credential_body_id == ctx.bodies["dev"]
    end

    test "takes the access away again", ctx do
      {:ok, _} =
        Lightning.Credentials.grant_body_to_project(
          ctx.project,
          ctx.credential.id,
          ctx.bodies["dev"],
          ctx.owner
        )

      {:ok, _} =
        Lightning.Credentials.grant_body_to_project(
          ctx.project,
          ctx.credential.id,
          nil,
          ctx.owner
        )

      assert is_nil(Repo.reload!(ctx.share).credential_body_id)
    end

    test "refuses a body belonging to another credential", ctx do
      other =
        insert(:credential, user: ctx.owner)
        |> with_body(%{name: "main", body: %{"key" => "someone else's"}})

      [their_body] = other.credential_bodies

      assert {:error, %Ecto.Changeset{} = changeset} =
               Lightning.Credentials.grant_body_to_project(
                 ctx.project,
                 ctx.credential.id,
                 their_body.id,
                 ctx.owner
               )

      assert "does not belong to this credential" in errors_on(changeset).credential_body_id

      assert is_nil(Repo.reload!(ctx.share).credential_body_id)
    end

    test "refuses someone who does not administer the project", ctx do
      editor = insert(:user)
      insert(:project_user, project: ctx.project, user: editor, role: :editor)

      # Granting access to a set of secrets is an administrative act. An editor
      # can write the job that spends the credential; they cannot decide which
      # values it spends.
      assert {:error, :unauthorized} =
               Lightning.Credentials.grant_body_to_project(
                 ctx.project,
                 ctx.credential.id,
                 ctx.bodies["dev"],
                 editor
               )

      assert is_nil(Repo.reload!(ctx.share).credential_body_id)
    end

    test "refuses a credential the project has no share of", ctx do
      unrelated = insert(:credential, user: ctx.owner)

      assert {:error, :not_found} =
               Lightning.Credentials.grant_body_to_project(
                 ctx.project,
                 unrelated.id,
                 ctx.bodies["dev"],
                 ctx.owner
               )
    end

    test "resolving refuses a body that is not this credential's", ctx do
      other =
        insert(:credential, user: ctx.owner)
        |> with_body(%{name: "main", body: %{"key" => "someone else's"}})

      [their_body] = other.credential_bodies

      # The composite foreign key already stops a share holding this pair, so
      # this is the read refusing it as well. Both matter: the constraint can be
      # dropped, and a caller can pass an id from anywhere.
      assert {:error, :no_credential_grant} =
               Lightning.Credentials.resolve_granted_body(
                 ctx.credential,
                 their_body.id
               )
    end

    test "resolving with no grant reads nothing", ctx do
      assert {:error, :no_credential_grant} =
               Lightning.Credentials.resolve_granted_body(ctx.credential, nil)
    end

    test "a granted set of values cannot be deleted, and says who is using it",
         ctx do
      {:ok, _} =
        Lightning.Credentials.grant_body_to_project(
          ctx.project,
          ctx.credential.id,
          ctx.bodies["dev"],
          ctx.owner
        )

      # Taking the values out from under a project that is granted them would
      # break it silently, so the form is told which projects are in the way
      # rather than raising.
      assert {:error, changeset} =
               Lightning.Credentials.update_credential(
                 ctx.credential,
                 %{
                   "credential_bodies" => [
                     %{"name" => "main", "body" => %{"key" => "live"}}
                   ],
                   "delete_environments" => ["dev"]
                 },
                 ctx.owner
               )

      assert %Ecto.Changeset{} = changeset
      assert Repo.get(Lightning.Credentials.CredentialBody, ctx.bodies["dev"])
    end

    test "an ungranted set of values can still be deleted", ctx do
      assert {:ok, _} =
               Lightning.Credentials.update_credential(
                 ctx.credential,
                 %{
                   "credential_bodies" => [
                     %{"name" => "main", "body" => %{"key" => "live"}}
                   ],
                   "delete_environments" => ["dev"]
                 },
                 ctx.owner
               )

      refute Repo.get(Lightning.Credentials.CredentialBody, ctx.bodies["dev"])
    end

    test "metadata refuses rather than crashing when there is no grant", ctx do
      # This reaches the editor's async metadata task, which cannot print a
      # tuple, so an unhandled reason there took the whole task down.
      assert {:error, %Lightning.MetadataService.Error{type: type}} =
               Lightning.MetadataService.fetch(
                 "@openfn/language-common",
                 ctx.credential,
                 nil
               )

      assert type == "no_credential_grant"
    end

    test "body_grants_for_project reports what each share reads", ctx do
      {:ok, _} =
        Lightning.Credentials.grant_body_to_project(
          ctx.project,
          ctx.credential.id,
          ctx.bodies["main"],
          ctx.owner
        )

      grants = Lightning.Credentials.body_grants_for_project(ctx.project)

      assert grants[ctx.credential.id] == ctx.bodies["main"]
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
