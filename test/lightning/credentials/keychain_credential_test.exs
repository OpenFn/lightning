defmodule Lightning.Credentials.KeychainCredentialTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.KeychainCredential

  describe "changeset/2" do
    test "name and path can't be blank" do
      errors =
        KeychainCredential.changeset(%KeychainCredential{}, %{}) |> errors_on()

      assert errors[:name] == ["can't be blank"]
      assert errors[:path] == ["can't be blank"]
      # created_by_id and project_id should be set via associations, not params
      refute errors[:created_by_id]
      refute errors[:project_id]
    end

    test "validates required fields with valid data" do
      project = insert(:project)
      user = insert(:user)

      keychain_credential =
        %KeychainCredential{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:created_by, user)
        |> Ecto.Changeset.put_assoc(:project, project)
        |> Ecto.Changeset.apply_changes()

      changeset =
        KeychainCredential.changeset(keychain_credential, %{
          name: "Test Keychain",
          path: "$.user_id"
        })

      assert changeset.valid?
    end

    test "validates unique constraint on name and project_id" do
      project = insert(:project)
      user = insert(:user)

      insert(:keychain_credential, %{
        name: "Unique Name",
        project: project
      })

      keychain_credential =
        %KeychainCredential{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:created_by, user)
        |> Ecto.Changeset.put_assoc(:project, project)
        |> Ecto.Changeset.apply_changes()

      changeset =
        KeychainCredential.changeset(keychain_credential, %{
          name: "Unique Name",
          path: "$.user_id"
        })

      assert {:error, changeset} = Repo.insert(changeset)

      assert errors_on(changeset)[:name] == [
               "has already been taken"
             ]
    end

    test "validates name length" do
      project = insert(:project)

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "",
          path: "$.user_id",
          project_id: project.id
        })

      assert errors_on(changeset)[:name] == ["can't be blank"]

      long_name = String.duplicate("a", 256)

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: long_name,
          path: "$.user_id",
          project_id: project.id
        })

      assert errors_on(changeset)[:name] == [
               "should be at most 255 character(s)"
             ]
    end

    test "validates path length" do
      project = insert(:project)
      user = insert(:user)

      keychain_credential =
        %KeychainCredential{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:created_by, user)
        |> Ecto.Changeset.put_assoc(:project, project)
        |> Ecto.Changeset.apply_changes()

      changeset =
        KeychainCredential.changeset(keychain_credential, %{
          name: "Test",
          path: ""
        })

      assert errors_on(changeset)[:path] == ["can't be blank"]

      long_path = "$.a" <> String.duplicate("b", 500)

      changeset =
        KeychainCredential.changeset(keychain_credential, %{
          name: "Test",
          path: long_path
        })

      errors = errors_on(changeset)[:path]
      assert "should be at most 500 character(s)" in errors
    end

    test "validates JSONPath format" do
      project = insert(:project)
      user = insert(:user)

      keychain_credential =
        %KeychainCredential{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:created_by, user)
        |> Ecto.Changeset.put_assoc(:project, project)
        |> Ecto.Changeset.apply_changes()

      # Valid JSONPath expressions
      valid_paths = [
        "$.user_id",
        "$.data.organization",
        "$.users[0].id",
        "$.data['user-id']",
        "$.data[?(@.type == 'admin')]",
        "$..user_id"
      ]

      for path <- valid_paths do
        changeset =
          KeychainCredential.changeset(keychain_credential, %{
            name: "Test",
            path: path
          })

        assert changeset.valid?, "Expected #{path} to be valid"
      end

      # Invalid JSONPath expressions
      invalid_paths = [
        # doesn't start with $
        "user_id",
        # invalid characters
        "$.user_id<>",
        # invalid characters
        "$.user_id{bad}",
        # empty string
        ""
      ]

      for path <- invalid_paths do
        changeset =
          KeychainCredential.changeset(keychain_credential, %{
            name: "Test",
            path: path
          })

        refute changeset.valid?, "Expected #{path} to be invalid"
        errors = errors_on(changeset)[:path] || []

        assert length(errors) > 0,
               "Expected validation errors for #{path}, got: #{inspect(errors)}"

        assert "Invalid JSONPath syntax" in errors or
                 "JSONPath must start with '$'" in errors or
                 "can't be blank" in errors
      end
    end

    test "validates default_credential belongs to same project" do
      project1 = insert(:project)
      project2 = insert(:project)
      user = insert(:user)

      credential1 = insert(:credential, user: user)
      credential2 = insert(:credential, user: user)

      # Associate credential1 with project1
      insert(:project_credential, project: project1, credential: credential1)
      # Associate credential2 with project2
      insert(:project_credential, project: project2, credential: credential2)

      # Valid: default credential belongs to same project
      keychain_credential1 =
        %KeychainCredential{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:created_by, user)
        |> Ecto.Changeset.put_assoc(:project, project1)
        |> Ecto.Changeset.apply_changes()

      changeset =
        KeychainCredential.changeset(keychain_credential1, %{
          name: "Test",
          path: "$.user_id",
          default_credential_id: credential1.id
        })

      assert changeset.valid?

      # Invalid: default credential belongs to different project
      keychain_credential2 =
        %KeychainCredential{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:created_by, user)
        |> Ecto.Changeset.put_assoc(:project, project1)
        |> Ecto.Changeset.apply_changes()

      changeset =
        KeychainCredential.changeset(keychain_credential2, %{
          name: "Test",
          path: "$.user_id",
          default_credential_id: credential2.id
        })

      refute changeset.valid?

      assert errors_on(changeset)[:default_credential_id] == [
               "must belong to the same project"
             ]
    end

    test "allows nil default_credential_id" do
      project = insert(:project)
      user = insert(:user)

      keychain_credential =
        %KeychainCredential{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:created_by, user)
        |> Ecto.Changeset.put_assoc(:project, project)
        |> Ecto.Changeset.apply_changes()

      changeset =
        KeychainCredential.changeset(keychain_credential, %{
          name: "Test",
          path: "$.user_id",
          default_credential_id: nil
        })

      assert changeset.valid?
    end

    # Foreign key constraints are now enforced by proper association handling
    # through the context functions rather than accepting raw IDs from params
  end

  describe "context functions" do
    test "new_keychain_credential/2 creates struct with proper associations" do
      user = insert(:user)
      project = insert(:project)

      keychain = Lightning.Credentials.new_keychain_credential(user, project)

      assert keychain.created_by_id == user.id
      assert keychain.project_id == project.id
      assert keychain.created_by == user
      assert keychain.project == project
    end

    test "create_keychain_credential/2 with valid params" do
      user = insert(:user)
      project = insert(:project)
      credential = insert(:credential, user: user)
      insert(:project_credential, project: project, credential: credential)

      new_keychain = Lightning.Credentials.new_keychain_credential(user, project)

      {:ok, keychain_credential} =
        Lightning.Credentials.create_keychain_credential(new_keychain, %{
          name: "Test Keychain",
          path: "$.user_id",
          default_credential_id: credential.id
        })

      assert keychain_credential.name == "Test Keychain"
      assert keychain_credential.path == "$.user_id"
      assert keychain_credential.default_credential_id == credential.id
      assert keychain_credential.created_by_id == user.id
      assert keychain_credential.project_id == project.id
    end

    test "create_keychain_credential/2 with validation errors" do
      user = insert(:user)
      project = insert(:project)

      new_keychain = Lightning.Credentials.new_keychain_credential(user, project)

      {:error, changeset} =
        Lightning.Credentials.create_keychain_credential(new_keychain, %{
          name: "",
          path: "invalid jsonpath",
          default_credential_id: ""
        })

      assert "can't be blank" in errors_on(changeset)[:name]
      assert "JSONPath must start with '$'" in errors_on(changeset)[:path]
    end

    test "create_keychain_credential/2 with nil default credential" do
      user = insert(:user)
      project = insert(:project)

      new_keychain = Lightning.Credentials.new_keychain_credential(user, project)

      {:ok, keychain_credential} =
        Lightning.Credentials.create_keychain_credential(new_keychain, %{
          name: "Test Keychain No Default",
          path: "$.org_id",
          default_credential_id: nil
        })

      assert keychain_credential.name == "Test Keychain No Default"
      assert keychain_credential.path == "$.org_id"
      assert keychain_credential.default_credential_id == nil
      assert keychain_credential.created_by_id == user.id
      assert keychain_credential.project_id == project.id
    end

    test "validates default credential belongs to same project in context" do
      user = insert(:user)
      project = insert(:project)
      other_project = insert(:project)
      other_credential = insert(:credential, user: user)

      insert(:project_credential,
        project: other_project,
        credential: other_credential
      )

      new_keychain = Lightning.Credentials.new_keychain_credential(user, project)

      {:error, changeset} =
        Lightning.Credentials.create_keychain_credential(new_keychain, %{
          name: "Test Keychain",
          path: "$.user_id",
          default_credential_id: other_credential.id
        })

      assert "must belong to the same project" in errors_on(changeset)[
               :default_credential_id
             ]
    end

    test "change_keychain_credential/2 validates properly" do
      user = insert(:user)
      project = insert(:project)

      new_keychain = Lightning.Credentials.new_keychain_credential(user, project)

      changeset =
        Lightning.Credentials.change_keychain_credential(new_keychain, %{
          name: "",
          path: "invalid jsonpath",
          default_credential_id: ""
        })
        |> Map.put(:action, :validate)

      assert "can't be blank" in errors_on(changeset)[:name]
      assert "JSONPath must start with '$'" in errors_on(changeset)[:path]
    end
  end

  describe "associations" do
    test "belongs_to project" do
      project = insert(:project)
      keychain_credential = insert(:keychain_credential, project: project)

      loaded_keychain = Repo.preload(keychain_credential, :project)
      assert loaded_keychain.project.id == project.id
    end

    test "belongs_to created_by" do
      user = insert(:user)
      keychain_credential = insert(:keychain_credential, created_by: user)

      loaded_keychain = Repo.preload(keychain_credential, :created_by)
      assert loaded_keychain.created_by.id == user.id
    end

    test "belongs_to default_credential" do
      project = insert(:project)
      user = insert(:user)
      credential = insert(:credential, user: user)
      insert(:project_credential, project: project, credential: credential)

      keychain_credential =
        insert(:keychain_credential,
          project: project,
          default_credential: credential
        )

      loaded_keychain = Repo.preload(keychain_credential, :default_credential)
      assert loaded_keychain.default_credential.id == credential.id
    end
  end

  describe "external_id uniqueness validation" do
    test "keychain resolver raises error when duplicate external_ids exist in same project" do
      # This test documents the behavior when duplicate external_ids exist
      # (which should be prevented by validation, but could occur from legacy data)
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      # Create credentials directly with insert to bypass validation
      # (simulating legacy data or direct DB manipulation)
      credential_a =
        insert(:credential,
          name: "Credential A",
          schema: "raw",
          external_id: "duplicate-id",
          user: user
        )
        |> with_body(%{name: "main", body: %{"key" => "value_a"}})

      credential_b =
        insert(:credential,
          name: "Credential B",
          schema: "raw",
          external_id: "duplicate-id",
          user: user
        )
        |> with_body(%{name: "main", body: %{"key" => "value_b"}})

      # Associate both credentials with the same project
      insert(:project_credential, project: project, credential: credential_a)
      insert(:project_credential, project: project, credential: credential_b)

      # Create a keychain credential
      keychain_credential =
        insert(:keychain_credential,
          name: "Test Keychain",
          path: "$.user_id",
          project: project,
          created_by: user
        )

      # Create workflow with the keychain credential
      %{jobs: [job]} =
        workflow =
        build(:workflow, project: project)
        |> with_job(%{keychain_credential: keychain_credential})
        |> insert()

      # Create a run with dataclip that matches the duplicate external_id
      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{
          dataclip:
            build(:dataclip, %{
              body: %{"user_id" => "duplicate-id"}
            }),
          starting_job: job
        })

      # The resolver should raise an error because Repo.one() finds multiple results
      assert_raise Ecto.MultipleResultsError, fn ->
        Lightning.Credentials.Resolver.resolve_credential(
          run,
          keychain_credential.id
        )
      end
    end
  end
end
