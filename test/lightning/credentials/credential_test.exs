defmodule Lightning.Credentials.CredentialTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials
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

  describe "OAuth validation" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)
      %{user: user, oauth_client: oauth_client}
    end

    test "oauth credentials require all required OAuth fields to be valid" do
      assert_invalid_oauth_credential(
        %{},
        "Missing required OAuth field: access_token"
      )

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "token_type" => "Bearer",
          "scope" => "read write"
        },
        "Missing required OAuth field: refresh_token"
      )

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "scope" => "read write"
        },
        "Missing required OAuth field: token_type"
      )

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "read write"
        },
        "Missing expiration field: either expires_in or expires_at is required"
      )

      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "scope" => "read write",
        "expires_at" => System.system_time(:second) + 3600
      })

      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "scope" => "read write",
        "expires_in" => 3600
      })
    end

    test "validates token_type field specifically" do
      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Basic",
          "scope" => "read write",
          "expires_in" => 3600
        },
        "Unsupported token type: 'Basic'. Expected 'Bearer'"
      )

      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "bearer",
        "scope" => "read write",
        "expires_in" => 3600
      })
    end

    test "validates token field values are non-empty" do
      assert_invalid_oauth_credential(
        %{
          "access_token" => "",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_in" => 3600
        },
        "access_token cannot be empty"
      )

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_in" => 3600
        },
        "refresh_token cannot be empty"
      )

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "",
          "expires_in" => 3600
        },
        "scope field cannot be empty"
      )
    end

    test "validates expires_in bounds" do
      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_in" => 0
        },
        "expires_in must be greater than 0 seconds, got: 0"
      )

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_in" => -300
        },
        "expires_in must be greater than 0 seconds, got: -300"
      )

      large_expires_in = 2 * 365 * 24 * 3600

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_in" => large_expires_in
        },
        "expires_in seems unreasonably long"
      )
    end

    test "validates expires_at bounds" do
      past_time = System.system_time(:second) - 2 * 24 * 3600

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_at" => past_time
        },
        "expires_at timestamp appears to be too far in the past"
      )

      future_time = System.system_time(:second) + 2 * 365 * 24 * 3600

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_at" => future_time
        },
        "expires_at timestamp appears to be too far in the future"
      )
    end

    test "validates scope grants when expected_scopes provided", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: token_data,
          oauth_client_id: oauth_client.id,
          expected_scopes: ["read", "write"],
          user_id: user.id
        })

      refute changeset.valid?
      errors = errors_on(changeset)

      assert errors[:oauth_token] == [
               "Missing required scopes: write. Please reauthorize and grant all selected permissions."
             ]
    end

    test "supports case-insensitive scope matching", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "READ write"
      }

      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: token_data,
          oauth_client_id: oauth_client.id,
          expected_scopes: ["read", "Write"],
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "works with scopes array format", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scopes" => ["read", "write", "admin"]
      }

      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: token_data,
          oauth_client_id: oauth_client.id,
          expected_scopes: ["read", "write"],
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "validates scopes array contains only strings" do
      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scopes" => ["read", 123, "write"]
        },
        "scopes array must contain only strings"
      )
    end

    test "skips scope validation when no expected_scopes provided", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: token_data,
          oauth_client_id: oauth_client.id,
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "non-OAuth credentials skip OAuth validation", %{user: user} do
      changeset =
        Credential.changeset(%Credential{}, %{
          name: "regular credential",
          schema: "raw",
          body: %{"key" => "value"},
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "updating existing OAuth credential with oauth_token_id skips token validation",
         %{
           user: user,
           oauth_client: oauth_client
         } do
      oauth_token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      changeset =
        Credential.changeset(%Credential{}, %{
          name: "existing oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token_id: oauth_token.id,
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "OAuth credential creation without token data fails", %{user: user} do
      attrs = %{
        name: "oauth credential",
        schema: "oauth",
        body: %{},
        user_id: user.id
      }

      changeset = Credential.changeset(%Credential{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:oauth_token] == ["OAuth credentials require token data"]
    end

    test "stores OAuth error details in virtual fields", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: token_data,
          oauth_client_id: oauth_client.id,
          expected_scopes: ["read", "write", "admin"],
          user_id: user.id
        })

      refute changeset.valid?

      assert get_change(changeset, :oauth_error_type) == :missing_scopes
      error_details = get_change(changeset, :oauth_error_details)
      assert error_details[:missing_scopes] == ["write", "admin"]
      assert error_details[:granted_scopes] == ["read"]
      assert error_details[:expected_scopes] == ["read", "write", "admin"]
    end

    test "handles invalid token format errors", %{user: user} do
      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: "invalid_token_format",
          user_id: user.id
        })

      refute changeset.valid?
      errors = errors_on(changeset)

      assert errors[:oauth_token] == [
               "OAuth token must be a valid map"
             ]

      assert get_change(changeset, :oauth_error_type) == :invalid_token_format
    end

    test "handles missing token data for OAuth credentials", %{user: user} do
      attrs = %{
        name: "oauth credential",
        schema: "oauth",
        body: %{},
        user_id: user.id
      }

      changeset = Credential.changeset(%Credential{}, attrs)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:oauth_token] == ["OAuth credentials require token data"]
    end

    test "accepts expires_in as string" do
      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "scope" => "read write",
        "expires_in" => "3600"
      })
    end

    test "accepts expires_at as Unix timestamp string" do
      future_time = System.system_time(:second) + 3600
      timestamp_string = Integer.to_string(future_time)

      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "scope" => "read write",
        "expires_at" => timestamp_string
      })
    end

    test "accepts ISO 8601 expires_at format" do
      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "scope" => "read write",
        "expires_at" => "2024-12-31T23:59:59Z"
      })
    end

    test "supports atom keys for oauth_token and expected_scopes", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: token_data,
          oauth_client_id: oauth_client.id,
          expected_scopes: ["read"],
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "handles expected_scopes as space-delimited string", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write admin"
      }

      changeset =
        Credentials.change_credential(%Credential{}, %{
          name: "oauth credential",
          schema: "oauth",
          body: %{},
          oauth_token: token_data,
          oauth_client_id: oauth_client.id,
          expected_scopes: "read write",
          user_id: user.id
        })

      assert changeset.valid?
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

  describe "virtual fields" do
    test "oauth_error_type and oauth_error_details are virtual fields" do
      credential = %Credential{
        oauth_error_type: :missing_scopes,
        oauth_error_details: %{missing_scopes: ["write"]}
      }

      assert credential.oauth_error_type == :missing_scopes
      assert credential.oauth_error_details == %{missing_scopes: ["write"]}

      schema_fields = Credential.__schema__(:fields)
      refute :oauth_error_type in schema_fields
      refute :oauth_error_details in schema_fields
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

  defp assert_invalid_oauth_credential(token_data, expected_message) do
    errors =
      Credentials.change_credential(%Credential{}, %{
        name: "oauth credential",
        schema: "oauth",
        oauth_token: token_data,
        user_id: insert(:user).id
      })
      |> errors_on()

    oauth_errors = errors[:oauth_token] || []

    assert Enum.any?(oauth_errors, fn error ->
             String.contains?(error, expected_message)
           end),
           "Expected error containing '#{expected_message}', but got: #{inspect(oauth_errors)}"
  end

  defp refute_invalid_oauth_credential(token_data) do
    errors =
      Credentials.change_credential(%Credential{}, %{
        name: "oauth credential",
        schema: "oauth",
        body: %{},
        oauth_token: token_data,
        user_id: insert(:user).id
      })
      |> errors_on()

    refute errors[:oauth_token],
           "Expected no OAuth errors, but got: #{inspect(errors[:oauth_token])}"
  end
end
