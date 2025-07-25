defmodule Lightning.Credentials.CredentialTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.Credential

  describe "changeset/2" do
    test "name, body, and user_id can't be blank" do
      errors = Credential.changeset(%Credential{}, %{}) |> errors_on()
      assert errors[:name] == ["can't be blank"]
      assert errors[:body] == ["can't be blank"]
      assert errors[:user_id] == ["can't be blank"]
    end

    test "validates required fields with valid data" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test Credential",
          body: %{"key" => "value"},
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "validates unique constraint on name and user_id" do
      user = insert(:user)

      insert(:credential, %{
        name: "Unique Name",
        user: user
      })

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Unique Name",
          body: %{"key" => "value"},
          user_id: user.id
        })

      assert {:error, changeset} = Repo.insert(changeset)

      assert errors_on(changeset)[:name] == [
               "you have another credential with the same name"
             ]
    end

    test "allows same name for different users" do
      user1 = insert(:user)
      user2 = insert(:user)

      insert(:credential, %{
        name: "Same Name",
        user: user1
      })

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Same Name",
          body: %{"key" => "value"},
          user_id: user2.id
        })

      assert changeset.valid?
    end

    test "validates name format" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Invalid@Name#",
          body: %{"key" => "value"},
          user_id: user.id
        })

      refute changeset.valid?

      assert errors_on(changeset)[:name] == [
               "credential name has invalid format"
             ]
    end

    test "allows valid name formats" do
      user = insert(:user)

      valid_names = [
        "ValidName",
        "Valid Name",
        "Valid-Name",
        "Valid_Name",
        "Valid123",
        "123Valid"
      ]

      for name <- valid_names do
        changeset =
          Credential.changeset(%Credential{}, %{
            name: name,
            body: %{"key" => "value"},
            user_id: user.id
          })

        assert changeset.valid?, "Name '#{name}' should be valid"
      end
    end

    test "validates assoc constraint for user" do
      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{"key" => "value"},
          user_id: Ecto.UUID.generate()
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert errors_on(changeset)[:user] == ["does not exist"]
    end

    test "casts production field" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{"key" => "value"},
          user_id: user.id,
          production: true
        })

      assert get_change(changeset, :production) == true
    end

    test "casts schema field" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{"key" => "value"},
          user_id: user.id,
          schema: "oauth"
        })

      assert get_change(changeset, :schema) == "oauth"
    end

    test "casts oauth_token_id field" do
      user = insert(:user)
      oauth_token = insert(:oauth_token, user: user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{"key" => "value"},
          user_id: user.id,
          oauth_token_id: oauth_token.id
        })

      assert get_change(changeset, :oauth_token_id) == oauth_token.id
    end

    test "casts scheduled_deletion field" do
      user = insert(:user)
      deletion_time = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{"key" => "value"},
          user_id: user.id,
          scheduled_deletion: deletion_time
        })

      assert get_change(changeset, :scheduled_deletion) == deletion_time
    end

    test "casts transfer_status field" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{"key" => "value"},
          user_id: user.id,
          transfer_status: :pending
        })

      assert get_change(changeset, :transfer_status) == :pending
    end

    test "casts project_credentials association" do
      user = insert(:user)
      project = insert(:project)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{"key" => "value"},
          user_id: user.id,
          project_credentials: [%{project_id: project.id}]
        })

      assert changeset.valid?
      assert length(get_change(changeset, :project_credentials, [])) == 1
    end
  end

  describe "encryption" do
    test "encrypts a credential at rest" do
      body = %{"foo" => [1]}

      %{id: credential_id, body: decoded_body} =
        Credential.changeset(%Credential{}, %{
          name: "Test Credential",
          body: body,
          user_id: insert(:user).id,
          schema: "raw"
        })
        |> Lightning.Repo.insert!()

      assert decoded_body == body

      persisted_body =
        from(c in Credential,
          select: type(c.body, :string),
          where: c.id == ^credential_id
        )
        |> Lightning.Repo.one!()

      refute persisted_body == body
    end

    test "decrypts credential body when loaded" do
      body = %{"secret" => "encrypted_value", "nested" => %{"key" => "value"}}
      user = insert(:user)

      credential =
        Credential.changeset(%Credential{}, %{
          name: "Encrypted Credential",
          body: body,
          user_id: user.id,
          schema: "raw"
        })
        |> Lightning.Repo.insert!()

      reloaded_credential = Repo.get!(Credential, credential.id)

      assert reloaded_credential.body == body
    end
  end

  describe "associations" do
    test "belongs_to user association" do
      user = insert(:user)
      credential = insert(:credential, user: user)

      loaded_credential =
        Credential
        |> preload(:user)
        |> Repo.get!(credential.id)

      assert loaded_credential.user.id == user.id
    end

    test "belongs_to oauth_token association" do
      user = insert(:user)
      oauth_token = insert(:oauth_token, user: user)

      credential =
        insert(:credential, %{
          user: user,
          oauth_token: oauth_token
        })

      loaded_credential =
        Credential
        |> preload(:oauth_token)
        |> Repo.get!(credential.id)

      assert loaded_credential.oauth_token.id == oauth_token.id
    end

    test "has_many project_credentials association" do
      user = insert(:user)
      credential = insert(:credential, user: user)
      project = insert(:project)

      project_credential =
        insert(:project_credential, %{
          credential: credential,
          project: project
        })

      loaded_credential =
        Credential
        |> preload(:project_credentials)
        |> Repo.get!(credential.id)

      assert length(loaded_credential.project_credentials) == 1

      assert hd(loaded_credential.project_credentials).id ==
               project_credential.id
    end

    test "has_many projects through project_credentials" do
      user = insert(:user)
      credential = insert(:credential, user: user)
      project = insert(:project)

      insert(:project_credential, %{
        credential: credential,
        project: project
      })

      loaded_credential =
        Credential
        |> preload(:projects)
        |> Repo.get!(credential.id)

      assert length(loaded_credential.projects) == 1
      assert hd(loaded_credential.projects).id == project.id
    end
  end

  describe "default values" do
    test "production defaults to false" do
      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{},
          user_id: insert(:user).id
        })

      credential = apply_changes(changeset)
      assert credential.production == false
    end

    test "can override production default" do
      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          body: %{},
          user_id: insert(:user).id,
          production: true
        })

      credential = apply_changes(changeset)
      assert credential.production == true
    end
  end
end
