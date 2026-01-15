defmodule Lightning.Credentials.CredentialTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories
  import Mox

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.CredentialBody

  setup :verify_on_exit!

  describe "changeset/2" do
    test "name and user_id can't be blank" do
      errors = Credential.changeset(%Credential{}, %{}) |> errors_on()
      assert errors[:name] == ["can't be blank"]
      assert errors[:user_id] == ["can't be blank"]
    end

    test "validates required fields with valid data" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test Credential",
          user_id: user.id,
          schema: "raw"
        })

      assert changeset.valid?
    end

    test "validates unique constraint on name and user_id" do
      user = insert(:user)

      insert(:credential,
        name: "Unique Name",
        user: user
      )

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Unique Name",
          user_id: user.id,
          schema: "raw"
        })

      assert {:error, changeset} = Repo.insert(changeset)

      assert errors_on(changeset)[:name] == [
               "you have another credential with the same name"
             ]
    end

    test "allows same name for different users" do
      user1 = insert(:user)
      user2 = insert(:user)

      insert(:credential,
        name: "Same Name",
        user: user1
      )

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Same Name",
          user_id: user2.id,
          schema: "raw"
        })

      assert changeset.valid?
    end

    test "validates name format" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Invalid@Name#",
          user_id: user.id,
          schema: "raw"
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
            user_id: user.id,
            schema: "raw"
          })

        assert changeset.valid?, "Name '#{name}' should be valid"
      end
    end

    test "validates assoc constraint for user" do
      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          user_id: Ecto.UUID.generate(),
          schema: "raw"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert errors_on(changeset)[:user] == ["does not exist"]
    end

    test "casts schema field" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          user_id: user.id,
          schema: "oauth"
        })

      assert get_change(changeset, :schema) == "oauth"
    end

    test "casts oauth_client_id field" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          user_id: user.id,
          schema: "oauth",
          oauth_client_id: oauth_client.id
        })

      assert get_change(changeset, :oauth_client_id) == oauth_client.id
    end

    test "casts scheduled_deletion field" do
      user = insert(:user)
      deletion_time = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          user_id: user.id,
          schema: "raw",
          scheduled_deletion: deletion_time
        })

      assert get_change(changeset, :scheduled_deletion) == deletion_time
    end

    test "casts transfer_status field" do
      user = insert(:user)

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "Test",
          user_id: user.id,
          schema: "raw",
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
          user_id: user.id,
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        })

      assert changeset.valid?
      assert length(get_change(changeset, :project_credentials, [])) == 1
    end
  end

  describe "credential_body changeset" do
    setup do
      user = insert(:user)
      credential = insert(:credential, user: user, schema: "raw")
      %{user: user, credential: credential}
    end

    test "credential_id and body can't be blank" do
      # Name has default "main", so only credential_id and body are truly required
      errors = CredentialBody.changeset(%CredentialBody{}, %{}) |> errors_on()
      assert errors[:credential_id] == ["can't be blank"]
      assert errors[:body] == ["can't be blank"]
    end

    test "validates credential body with valid data", %{credential: credential} do
      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: %{"key" => "value"}
        })

      assert changeset.valid?
    end

    test "validates unique constraint on credential_id and name", %{
      credential: credential
    } do
      # Insert first body
      credential
      |> with_body(%{
        name: "production",
        body: %{"key" => "value"}
      })

      # Try to insert duplicate environment for same credential
      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: %{"key" => "other_value"}
        })

      assert {:error, changeset} = Repo.insert(changeset)

      # Unique constraint error will be on the composite index
      errors = errors_on(changeset)

      assert errors[:credential_id] == ["has already been taken"] or
               errors[:name] == ["has already been taken"]
    end

    test "allows same environment name for different credentials", %{user: user} do
      _credential1 =
        insert(:credential, user: user, schema: "raw")
        |> with_body(%{name: "production", body: %{"key" => "value1"}})

      credential2 = insert(:credential, user: user, schema: "raw")

      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential2.id,
          name: "production",
          body: %{"key" => "value2"}
        })

      assert changeset.valid?
      assert {:ok, _} = Repo.insert(changeset)
    end

    test "validates environment name format", %{credential: credential} do
      # Based on regex: ~r/^[a-z0-9][a-z0-9_-]{0,31}$/
      invalid_names = [
        # uppercase
        "Prod",
        # uppercase
        "STAGING",
        # starts with underscore
        "_dev",
        # starts with dash
        "-test",
        # has slash
        "prod/staging",
        # has backslash
        "prod\\staging",
        # has @
        "prod@staging",
        # has dot
        "prod.staging",
        # has space
        "prod staging",
        # too long (33 chars)
        String.duplicate("a", 33)
      ]

      for name <- invalid_names do
        changeset =
          CredentialBody.changeset(%CredentialBody{}, %{
            credential_id: credential.id,
            name: name,
            body: %{"key" => "value"}
          })

        refute changeset.valid?,
               "Environment name '#{name}' should be invalid"

        assert errors_on(changeset)[:name] == ["must be a short slug"]
      end
    end

    test "allows valid environment name formats", %{credential: credential} do
      valid_names = [
        "production",
        "staging",
        "dev",
        "test",
        "prod-eu",
        "staging_us",
        "env123",
        "main",
        "prod-v2",
        "staging-2024",
        "env_test_1",
        # single char
        "a",
        # max length (32 chars)
        String.duplicate("a", 32)
      ]

      for name <- valid_names do
        changeset =
          CredentialBody.changeset(%CredentialBody{}, %{
            credential_id: credential.id,
            name: name,
            body: %{"key" => "value"}
          })

        assert changeset.valid?,
               "Environment name '#{name}' should be valid"
      end
    end

    test "validates credential body doesn't exceed max sensitive values", %{
      credential: credential
    } do
      # Mock config to limit to 5 sensitive values for easier testing
      Lightning.MockConfig
      |> expect(:max_credential_sensitive_values, 2, fn -> 5 end)

      # Create a body with exactly 1 safe value 5 sensitive values (at the limit)
      acceptable_body = %{
        "username" => "user@example.com",
        "api_key_1" => "secret_1",
        "api_key_2" => "secret_2",
        "api_key_3" => "secret_3",
        "api_key_4" => "secret_4",
        "api_key_5" => "secret_5"
      }

      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: acceptable_body
        })

      assert changeset.valid?

      # Create a body with 6 sensitive values (exceeds limit of 5)
      large_body = %{
        "username" => "user@example.com",
        "api_key_1" => "secret_1",
        "api_key_2" => "secret_2",
        "api_key_3" => "secret_3",
        "api_key_4" => "secret_4",
        "api_key_5" => "secret_5",
        "api_key_6" => "secret_6"
      }

      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: large_body
        })

      refute changeset.valid?
      errors = errors_on(changeset)

      assert [error_message] = errors[:body]

      assert error_message =~ "contains too many sensitive keys (6)"
      assert error_message =~ "Max allowed is 5"
    end

    test "validates foreign key constraint for credential_id" do
      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: Ecto.UUID.generate(),
          name: "production",
          body: %{"key" => "value"}
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert errors_on(changeset)[:credential] == ["does not exist"]
    end

    test "body must be a map", %{credential: credential} do
      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: "not a map"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:body] == ["is invalid"]
    end

    test "accepts empty map as body", %{credential: credential} do
      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: %{}
        })

      assert changeset.valid?
    end

    test "name defaults to 'main' when not provided", %{credential: credential} do
      changeset =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          body: %{"key" => "value"}
        })

      assert changeset.valid?

      {:ok, credential_body} = Repo.insert(changeset)
      assert credential_body.name == "main"
    end

    test "body is encrypted at rest", %{credential: credential} do
      body = %{"secret" => "sensitive_data"}

      {:ok, credential_body} =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: body
        })
        |> Repo.insert()

      persisted_body =
        from(cb in CredentialBody,
          select: type(cb.body, :string),
          where: cb.id == ^credential_body.id
        )
        |> Repo.one!()

      refute persisted_body == Jason.encode!(body)

      loaded = Repo.get!(CredentialBody, credential_body.id)
      assert loaded.body == body
    end

    test "updates to body are encrypted", %{credential: credential} do
      original_body = %{"key" => "original"}
      updated_body = %{"key" => "updated"}

      {:ok, credential_body} =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: original_body
        })
        |> Repo.insert()

      {:ok, updated} =
        credential_body
        |> CredentialBody.changeset(%{body: updated_body})
        |> Repo.update()

      reloaded = Repo.get!(CredentialBody, updated.id)
      assert reloaded.body == updated_body
    end

    test "body is required and cannot be nil", %{credential: credential} do
      {:ok, credential_body} =
        CredentialBody.changeset(%CredentialBody{}, %{
          credential_id: credential.id,
          name: "production",
          body: %{"key" => "value"}
        })
        |> Repo.insert()

      changeset = CredentialBody.changeset(credential_body, %{body: nil})

      refute changeset.valid?
      assert errors_on(changeset)[:body] == ["can't be blank"]
    end
  end

  describe "encryption" do
    test "encrypts a credential body at rest" do
      body = %{"foo" => [1]}
      user = insert(:user)

      credential =
        insert(:credential, user: user, schema: "raw")
        |> with_body(%{
          name: "main",
          body: body
        })

      credential_body =
        Lightning.Credentials.get_credential_body(credential.id, "main")

      assert credential_body.body == body

      persisted_body =
        from(cb in Lightning.Credentials.CredentialBody,
          select: type(cb.body, :string),
          where: cb.credential_id == ^credential.id and cb.name == "main"
        )
        |> Lightning.Repo.one!()

      refute persisted_body == Jason.encode!(body)
    end

    test "decrypts credential body when loaded" do
      body = %{"secret" => "encrypted_value", "nested" => %{"key" => "value"}}
      user = insert(:user)

      credential =
        insert(:credential, user: user, schema: "raw")
        |> with_body(%{
          name: "production",
          body: body
        })

      reloaded_credential_body =
        Lightning.Credentials.get_credential_body(credential.id, "production")

      assert reloaded_credential_body.body == body
    end

    test "encrypts multiple environment bodies independently" do
      prod_body = %{"env" => "production", "secret" => "prod_secret"}
      staging_body = %{"env" => "staging", "secret" => "staging_secret"}
      user = insert(:user)

      credential =
        insert(:credential, user: user, schema: "raw")
        |> with_body(%{name: "production", body: prod_body})
        |> with_body(%{name: "staging", body: staging_body})

      persisted_bodies =
        from(cb in Lightning.Credentials.CredentialBody,
          select: {cb.name, type(cb.body, :string)},
          where: cb.credential_id == ^credential.id
        )
        |> Lightning.Repo.all()
        |> Map.new()

      refute persisted_bodies["production"] == Jason.encode!(prod_body)
      refute persisted_bodies["staging"] == Jason.encode!(staging_body)

      prod_loaded =
        Lightning.Credentials.get_credential_body(credential.id, "production")

      staging_loaded =
        Lightning.Credentials.get_credential_body(credential.id, "staging")

      assert prod_loaded.body == prod_body
      assert staging_loaded.body == staging_body
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

    test "belongs_to oauth_client association" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          oauth_client: oauth_client
        )

      loaded_credential =
        Credential
        |> preload(:oauth_client)
        |> Repo.get!(credential.id)

      assert loaded_credential.oauth_client.id == oauth_client.id
    end

    test "has_many credential_bodies association" do
      user = insert(:user)

      credential =
        insert(:credential, user: user)
        |> with_body(%{
          name: "production",
          body: %{"api_key" => "prod_key"}
        })
        |> with_body(%{
          name: "staging",
          body: %{"api_key" => "staging_key"}
        })

      loaded_credential =
        Credential
        |> preload(:credential_bodies)
        |> Repo.get!(credential.id)

      assert length(loaded_credential.credential_bodies) == 2

      env_names = Enum.map(loaded_credential.credential_bodies, & &1.name)
      assert "production" in env_names
      assert "staging" in env_names
    end

    test "has_many project_credentials association" do
      user = insert(:user)
      credential = insert(:credential, user: user)
      project = insert(:project)

      project_credential =
        insert(:project_credential,
          credential: credential,
          project: project
        )

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

      insert(:project_credential,
        credential: credential,
        project: project
      )

      loaded_credential =
        Credential
        |> preload(:projects)
        |> Repo.get!(credential.id)

      assert length(loaded_credential.projects) == 1
      assert hd(loaded_credential.projects).id == project.id
    end
  end
end
