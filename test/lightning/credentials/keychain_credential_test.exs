defmodule Lightning.Credentials.KeychainCredentialTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.KeychainCredential

  describe "changeset/2" do
    test "name, path, created_by_id, and project_id can't be blank" do
      errors =
        KeychainCredential.changeset(%KeychainCredential{}, %{}) |> errors_on()

      assert errors[:name] == ["can't be blank"]
      assert errors[:path] == ["can't be blank"]
      assert errors[:created_by_id] == ["can't be blank"]
      assert errors[:project_id] == ["can't be blank"]
    end

    test "validates required fields with valid data" do
      project = insert(:project)
      user = insert(:user)

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test Keychain",
          path: "$.user_id",
          created_by_id: user.id,
          project_id: project.id
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

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Unique Name",
          path: "$.user_id",
          created_by_id: user.id,
          project_id: project.id
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

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test",
          path: "",
          created_by_id: user.id,
          project_id: project.id
        })

      assert errors_on(changeset)[:path] == ["can't be blank"]

      long_path = "$.a" <> String.duplicate("b", 500)

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test",
          path: long_path,
          created_by_id: user.id,
          project_id: project.id
        })

      errors = errors_on(changeset)[:path]
      assert "should be at most 500 character(s)" in errors
    end

    test "validates JSONPath format" do
      project = insert(:project)
      user = insert(:user)

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
          KeychainCredential.changeset(%KeychainCredential{}, %{
            name: "Test",
            path: path,
            created_by_id: user.id,
            project_id: project.id
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
          KeychainCredential.changeset(%KeychainCredential{}, %{
            name: "Test",
            path: path,
            created_by_id: user.id,
            project_id: project.id
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
      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test",
          path: "$.user_id",
          created_by_id: user.id,
          project_id: project1.id,
          default_credential_id: credential1.id
        })

      assert changeset.valid?

      # Invalid: default credential belongs to different project
      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test",
          path: "$.user_id",
          project_id: project1.id,
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

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test",
          path: "$.user_id",
          created_by_id: user.id,
          project_id: project.id,
          default_credential_id: nil
        })

      assert changeset.valid?
    end

    test "validates foreign key constraints" do
      user = insert(:user)

      # Invalid project_id
      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test",
          path: "$.user_id",
          created_by_id: user.id,
          project_id: Ecto.UUID.generate()
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert errors_on(changeset)[:project_id] == ["does not exist"]

      # Invalid default_credential_id (non-existent credential)
      project = insert(:project)

      changeset =
        KeychainCredential.changeset(%KeychainCredential{}, %{
          name: "Test",
          path: "$.user_id",
          created_by_id: user.id,
          project_id: project.id,
          default_credential_id: Ecto.UUID.generate()
        })

      # This will fail due to the custom validation that checks project association
      refute changeset.valid?

      assert errors_on(changeset)[:default_credential_id] == [
               "must belong to the same project"
             ]
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
end
