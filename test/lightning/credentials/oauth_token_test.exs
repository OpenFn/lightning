defmodule Lightning.Credentials.OauthTokenTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.OauthToken
  alias Lightning.Credentials.OauthValidation

  describe "changeset/2" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_attrs = %{
        body: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      {:ok, user: user, oauth_client: oauth_client, valid_attrs: valid_attrs}
    end

    test "with valid attributes creates a valid changeset", %{
      valid_attrs: valid_attrs
    } do
      changeset = OauthToken.changeset(%OauthToken{}, valid_attrs)
      assert changeset.valid?
    end

    test "changeset/1 with single argument calls changeset/2 with empty struct" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset1 = OauthToken.changeset(attrs)
      changeset2 = OauthToken.changeset(%OauthToken{}, attrs)

      assert changeset1.data == changeset2.data
      assert changeset1.changes == changeset2.changes
    end

    test "requires body, oauth_client_id and user_id" do
      changeset = OauthToken.changeset(%OauthToken{}, %{})

      errors = errors_on(changeset)
      assert "OAuth token body is required" in errors[:body]
      assert "can't be blank" in errors[:body]
      assert "can't be blank" in errors[:oauth_client_id]
      assert "can't be blank" in errors[:user_id]
    end

    test "automatically extracts scopes from body when not provided", %{
      valid_attrs: valid_attrs
    } do
      attrs_without_scopes = Map.delete(valid_attrs, :scopes)
      changeset = OauthToken.changeset(%OauthToken{}, attrs_without_scopes)

      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write"]
    end

    test "normalizes provided scopes", %{valid_attrs: valid_attrs} do
      attrs_with_mixed_case_scopes =
        valid_attrs
        |> Map.put(:scopes, ["READ", "Write"])
        |> put_in([:body, "scope"], "read write")

      changeset =
        OauthToken.changeset(%OauthToken{}, attrs_with_mixed_case_scopes)

      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write"]
    end

    test "validates scope consistency between body and scopes field", %{
      valid_attrs: valid_attrs
    } do
      inconsistent_attrs =
        valid_attrs
        |> Map.put(:scopes, ["admin", "delete"])
        |> put_in([:body, "scope"], "read write")

      changeset = OauthToken.changeset(%OauthToken{}, inconsistent_attrs)

      refute changeset.valid?

      assert {"scopes field does not match scopes in token body", []} =
               changeset.errors[:scopes]
    end

    test "accepts scopes array format in body", %{valid_attrs: valid_attrs} do
      attrs_with_scopes_array =
        put_in(valid_attrs, [:body, "scopes"], ["read", "write"])
        |> update_in([:body], &Map.delete(&1, "scope"))

      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_scopes_array)
      assert changeset.valid?
    end

    test "validates associations exist", %{user: _user, valid_attrs: valid_attrs} do
      attrs_with_bad_client =
        Map.put(valid_attrs, :oauth_client_id, Ecto.UUID.generate())

      {:error, changeset} =
        %OauthToken{}
        |> OauthToken.changeset(attrs_with_bad_client)
        |> Lightning.Repo.insert()

      refute changeset.valid?
      assert {"does not exist", _} = changeset.errors[:oauth_client]

      attrs_with_bad_user = Map.put(valid_attrs, :user_id, Ecto.UUID.generate())

      {:error, changeset} =
        %OauthToken{}
        |> OauthToken.changeset(attrs_with_bad_user)
        |> Lightning.Repo.insert()

      refute changeset.valid?
      assert {"does not exist", _} = changeset.errors[:user]
    end

    test "validates OAuth body format - non-map body", %{
      valid_attrs: valid_attrs
    } do
      invalid_attrs = Map.put(valid_attrs, :body, "not a map")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"OAuth token body is required", []} = changeset.errors[:body]
    end

    test "validates OAuth body format - nil body", %{valid_attrs: valid_attrs} do
      invalid_attrs = Map.put(valid_attrs, :body, nil)
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      errors = errors_on(changeset)
      assert "OAuth token body is required" in errors[:body]
      assert "can't be blank" in errors[:body]
    end

    test "validates all required OAuth fields", %{valid_attrs: valid_attrs} do
      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]

      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: refresh_token", []} =
               changeset.errors[:body]

      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: token_type", []} =
               changeset.errors[:body]
    end

    test "validates token_type is Bearer", %{valid_attrs: valid_attrs} do
      invalid_attrs = put_in(valid_attrs, [:body, "token_type"], "Basic")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Unsupported token type: 'Basic'. Expected 'Bearer'", []} =
               changeset.errors[:body]
    end

    test "validates empty token fields", %{valid_attrs: valid_attrs} do
      invalid_attrs = put_in(valid_attrs, [:body, "access_token"], "")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?
      assert {"access_token cannot be empty", []} = changeset.errors[:body]

      invalid_attrs = put_in(valid_attrs, [:body, "scope"], "")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?
      assert {"scope field cannot be empty", []} = changeset.errors[:body]
    end

    test "validates expires_in bounds", %{valid_attrs: valid_attrs} do
      invalid_attrs = put_in(valid_attrs, [:body, "expires_in"], 0)
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"expires_in must be greater than 0 seconds, got: 0", []} =
               changeset.errors[:body]

      invalid_attrs = put_in(valid_attrs, [:body, "expires_in"], -300)
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"expires_in must be greater than 0 seconds, got: -300", []} =
               changeset.errors[:body]
    end

    test "accepts expires_at instead of expires_in", %{valid_attrs: valid_attrs} do
      future_time = System.system_time(:second) + 3600

      attrs_with_expires_at =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_expires_at)
      assert changeset.valid?
    end

    test "accepts expires_in as string", %{valid_attrs: valid_attrs} do
      attrs_with_string_expires_in =
        put_in(valid_attrs, [:body, "expires_in"], "3600")

      changeset =
        OauthToken.changeset(%OauthToken{}, attrs_with_string_expires_in)

      assert changeset.valid?
    end

    test "populates virtual error fields on validation failure", %{
      valid_attrs: valid_attrs
    } do
      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)

      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]

      assert get_change(changeset, :oauth_error_type) == :missing_access_token
    end

    test "casts last_refreshed field", %{valid_attrs: valid_attrs} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attrs_with_last_refreshed = Map.put(valid_attrs, :last_refreshed, now)

      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_last_refreshed)
      assert changeset.valid?
      assert get_change(changeset, :last_refreshed) == now
    end
  end

  describe "update_token_changeset/2" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read", "write"],
          body: %{
            "access_token" => "access_token_123",
            "refresh_token" => "refresh_token_123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read write"
          }
        )

      {:ok, token: token}
    end

    test "updates token body and sets last_refreshed", %{token: token} do
      new_token_data = %{
        "access_token" => "new_access_token",
        "refresh_token" => "new_refresh_token",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "read write execute"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)

      assert changeset.valid?
      assert changeset.changes.body == new_token_data
      assert changeset.changes.scopes == ["read", "write", "execute"]
      assert get_change(changeset, :last_refreshed) != nil
    end

    test "preserves existing refresh_token when new token doesn't have one", %{
      token: token
    } do
      new_token_data = %{
        "access_token" => "new_access_token",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "read write execute"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)
      assert changeset.valid?

      expected_body = %{
        "refresh_token" => "refresh_token_123",
        "access_token" => "new_access_token",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "read write execute"
      }

      assert changeset.changes.body == expected_body
      assert changeset.changes.scopes == ["read", "write", "execute"]
    end

    test "handles token with scopes array format", %{token: token} do
      new_token_data = %{
        "access_token" => "new_access_token",
        "refresh_token" => "new_refresh_token",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scopes" => ["read", "write", "admin"]
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)
      assert changeset.valid?
      assert changeset.changes.body == new_token_data
      assert changeset.changes.scopes == ["read", "write", "admin"]
    end

    test "validates updated token body", %{token: token} do
      invalid_token = %{
        "refresh_token" => "new_refresh_token",
        "token_type" => "Bearer",
        "scope" => "read write"
      }

      changeset = OauthToken.update_token_changeset(token, invalid_token)
      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]
    end

    test "handles empty map input preserves refresh_token", %{token: token} do
      changeset = OauthToken.update_token_changeset(token, %{})

      expected_body = %{"refresh_token" => "refresh_token_123"}
      assert get_change(changeset, :body) == expected_body
      assert get_change(changeset, :scopes) == []
    end

    test "handles token without refresh_token gracefully" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token_without_refresh =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "access_token_123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          }
        )

      new_token_data = %{
        "access_token" => "new_access_token",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "read"
      }

      changeset =
        OauthToken.update_token_changeset(token_without_refresh, new_token_data)

      assert changeset.changes.body == new_token_data
    end

    test "automatically sets last_refreshed timestamp" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "old_token",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          last_refreshed: DateTime.add(DateTime.utc_now(), -1, :hour)
        )

      new_token_data = %{
        "access_token" => "new_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)

      assert changeset.valid?
      new_last_refreshed = get_change(changeset, :last_refreshed)
      assert new_last_refreshed != nil

      age_seconds =
        DateTime.diff(DateTime.utc_now(), new_last_refreshed, :second)

      assert age_seconds < 60
    end

    test "validates missing expiration in update" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "token123",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          }
        )

      invalid_token = %{
        "access_token" => "new_token",
        "refresh_token" => "new_refresh",
        "token_type" => "Bearer",
        "scope" => "read"
      }

      changeset = OauthToken.update_token_changeset(token, invalid_token)
      refute changeset.valid?

      assert {"Missing expiration field: either expires_in or expires_at is required",
              []} = changeset.errors[:body]
    end

    test "normalizes scopes during update" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "token123",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          }
        )

      new_token_data = %{
        "access_token" => "new_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "READ Write ADMIN"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]
    end
  end

  describe "expired?/1" do
    test "returns true for token with past expires_at timestamp" do
      past_time = System.system_time(:second) - 3600

      token = %OauthToken{
        body: %{"expires_at" => past_time},
        updated_at: DateTime.utc_now()
      }

      assert OauthToken.expired?(token)
    end

    test "returns false for token with future expires_at timestamp" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.expired?(token)
    end

    test "handles expires_at as string" do
      past_time = System.system_time(:second) - 3600

      token = %OauthToken{
        body: %{"expires_at" => Integer.to_string(past_time)},
        updated_at: DateTime.utc_now()
      }

      assert OauthToken.expired?(token)
    end

    test "handles future expires_at as string" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{"expires_at" => Integer.to_string(future_time)},
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.expired?(token)
    end

    test "returns true for token with expired expires_in" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        updated_at: DateTime.add(DateTime.utc_now(), -7200, :second)
      }

      assert OauthToken.expired?(token)
    end

    test "returns false for token with valid expires_in" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        updated_at: DateTime.add(DateTime.utc_now(), -1800, :second)
      }

      refute OauthToken.expired?(token)
    end

    test "handles expires_in as string" do
      token = %OauthToken{
        body: %{"expires_in" => "3600"},
        updated_at: DateTime.add(DateTime.utc_now(), -7200, :second)
      }

      assert OauthToken.expired?(token)
    end

    test "handles valid expires_in as string" do
      token = %OauthToken{
        body: %{"expires_in" => "3600"},
        updated_at: DateTime.add(DateTime.utc_now(), -1800, :second)
      }

      refute OauthToken.expired?(token)
    end

    test "returns false for token without expiration data" do
      token = %OauthToken{
        body: %{"access_token" => "token"},
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.expired?(token)
    end

    test "returns false for token with nil updated_at" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        updated_at: nil
      }

      refute OauthToken.expired?(token)
    end

    test "handles malformed expires_at gracefully" do
      token = %OauthToken{
        body: %{"expires_at" => "not_a_number"},
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.expired?(token)
    end

    test "handles malformed expires_in gracefully" do
      token = %OauthToken{
        body: %{"expires_in" => "not_a_number"},
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.expired?(token)
    end

    test "returns true for token with zero expires_in" do
      token = %OauthToken{
        body: %{"expires_in" => 0},
        updated_at: DateTime.utc_now()
      }

      assert OauthToken.expired?(token)
    end

    test "returns true for token with negative expires_in" do
      token = %OauthToken{
        body: %{"expires_in" => -300},
        updated_at: DateTime.utc_now()
      }

      assert OauthToken.expired?(token)
    end

    test "handles edge case where token just expired" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        updated_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      }

      assert OauthToken.expired?(token)
    end

    test "handles edge case where token expires very soon" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        updated_at: DateTime.add(DateTime.utc_now(), -3599, :second)
      }

      refute OauthToken.expired?(token)
    end

    test "prefers expires_at over expires_in when both present" do
      past_expires_at = System.system_time(:second) - 1800

      token = %OauthToken{
        body: %{
          "expires_in" => 7200,
          "expires_at" => past_expires_at
        },
        updated_at: DateTime.add(DateTime.utc_now(), -600, :second)
      }

      assert OauthToken.expired?(token)
    end
  end

  describe "valid?/1" do
    test "returns true for valid non-expired token" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      assert OauthToken.valid?(token)
    end

    test "returns false for expired token" do
      past_time = System.system_time(:second) - 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_at" => past_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token with missing required fields" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token missing access_token" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token missing refresh_token" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token missing token_type" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token missing scope" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_at" => future_time
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token with unsupported token_type" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Basic",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token with empty access_token" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token with empty scope" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scope" => ""
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "works with expires_in instead of expires_at" do
      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        updated_at: DateTime.add(DateTime.utc_now(), -1800, :second)
      }

      assert OauthToken.valid?(token)
    end

    test "works with scopes array format" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scopes" => ["read", "write"]
        },
        updated_at: DateTime.utc_now()
      }

      assert OauthToken.valid?(token)
    end

    test "returns false for token with nil body" do
      token = %OauthToken{
        body: nil,
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "returns false for token with non-map body" do
      token = %OauthToken{
        body: "not_a_map",
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(token)
    end

    test "handles case-insensitive Bearer token type" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "bearer",
          "expires_at" => future_time,
          "scope" => "read write"
        },
        updated_at: DateTime.utc_now()
      }

      assert OauthToken.valid?(token)
    end
  end

  describe "needs_refresh?/2" do
    test "returns true for token that was never refreshed" do
      token = %OauthToken{last_refreshed: nil}
      assert OauthToken.needs_refresh?(token)
    end

    test "returns true for token older than max age" do
      old_time = DateTime.add(DateTime.utc_now(), -2, :hour)
      token = %OauthToken{last_refreshed: old_time}
      assert OauthToken.needs_refresh?(token, 1)
    end

    test "returns false for recently refreshed token" do
      recent_time = DateTime.add(DateTime.utc_now(), -30, :minute)
      token = %OauthToken{last_refreshed: recent_time}
      refute OauthToken.needs_refresh?(token, 1)
    end

    test "uses default max age of 1 hour" do
      old_time = DateTime.add(DateTime.utc_now(), -90, :minute)
      token = %OauthToken{last_refreshed: old_time}
      assert OauthToken.needs_refresh?(token)
    end

    test "returns true for token refreshed exactly at max age" do
      exact_time = DateTime.add(DateTime.utc_now(), -1, :hour)
      token = %OauthToken{last_refreshed: exact_time}
      assert OauthToken.needs_refresh?(token, 1)
    end

    test "handles very recent refresh" do
      very_recent = DateTime.add(DateTime.utc_now(), -1, :minute)
      token = %OauthToken{last_refreshed: very_recent}
      refute OauthToken.needs_refresh?(token, 1)
    end

    test "works with different max age values" do
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)
      token = %OauthToken{last_refreshed: two_hours_ago}

      assert OauthToken.needs_refresh?(token, 1)
      refute OauthToken.needs_refresh?(token, 3)
    end

    test "handles max age of 0 (always needs refresh)" do
      recent_time = DateTime.add(DateTime.utc_now(), -1, :minute)
      token = %OauthToken{last_refreshed: recent_time}
      assert OauthToken.needs_refresh?(token, 0)
    end

    test "handles fractional hours correctly" do
      thirty_minutes_ago = DateTime.add(DateTime.utc_now(), -30, :minute)
      token = %OauthToken{last_refreshed: thirty_minutes_ago}
      refute OauthToken.needs_refresh?(token, 1)
    end

    test "handles edge case of exactly one hour" do
      one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
      token = %OauthToken{last_refreshed: one_hour_ago}
      assert OauthToken.needs_refresh?(token, 1)
    end

    test "handles very large max age" do
      one_day_ago = DateTime.add(DateTime.utc_now(), -24, :hour)
      token = %OauthToken{last_refreshed: one_day_ago}
      refute OauthToken.needs_refresh?(token, 48)
    end

    test "handles negative max age gracefully" do
      recent_time = DateTime.add(DateTime.utc_now(), -30, :minute)
      token = %OauthToken{last_refreshed: recent_time}
      assert OauthToken.needs_refresh?(token, -1)
    end
  end

  describe "stale_or_expired?/2" do
    test "returns true for expired token" do
      past_time = System.system_time(:second) - 3600

      token = %OauthToken{
        body: %{"expires_at" => past_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: DateTime.utc_now()
      }

      assert OauthToken.stale_or_expired?(token)
    end

    test "returns true for stale token" do
      future_time = System.system_time(:second) + 3600
      old_refresh = DateTime.add(DateTime.utc_now(), -2, :hour)

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: old_refresh
      }

      assert OauthToken.stale_or_expired?(token, 1)
    end

    test "returns false for fresh valid token" do
      future_time = System.system_time(:second) + 3600
      recent_refresh = DateTime.add(DateTime.utc_now(), -30, :minute)

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: recent_refresh
      }

      refute OauthToken.stale_or_expired?(token, 1)
    end

    test "returns true when both expired and stale" do
      past_time = System.system_time(:second) - 1800
      old_refresh = DateTime.add(DateTime.utc_now(), -2, :hour)

      token = %OauthToken{
        body: %{"expires_at" => past_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: old_refresh
      }

      assert OauthToken.stale_or_expired?(token, 1)
    end

    test "returns true for expired token even if recently refreshed" do
      past_time = System.system_time(:second) - 1800
      recent_refresh = DateTime.add(DateTime.utc_now(), -15, :minute)

      token = %OauthToken{
        body: %{"expires_at" => past_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: recent_refresh
      }

      assert OauthToken.stale_or_expired?(token, 1)
    end

    test "returns true for stale token even if not expired" do
      future_time = System.system_time(:second) + 7200
      old_refresh = DateTime.add(DateTime.utc_now(), -3, :hour)

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: old_refresh
      }

      assert OauthToken.stale_or_expired?(token, 1)
    end

    test "works with expires_in format" do
      recent_refresh = DateTime.add(DateTime.utc_now(), -30, :minute)

      token = %OauthToken{
        body: %{"expires_in" => 3600},
        updated_at: DateTime.add(DateTime.utc_now(), -45, :minute),
        last_refreshed: recent_refresh
      }

      refute OauthToken.stale_or_expired?(token, 1)
    end

    test "handles token that was never refreshed" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: nil
      }

      assert OauthToken.stale_or_expired?(token, 1)
    end

    test "uses default max age of 1 hour" do
      future_time = System.system_time(:second) + 3600
      old_refresh = DateTime.add(DateTime.utc_now(), -90, :minute)

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: old_refresh
      }

      assert OauthToken.stale_or_expired?(token)
    end

    test "works with different max age values" do
      future_time = System.system_time(:second) + 3600
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: two_hours_ago
      }

      assert OauthToken.stale_or_expired?(token, 1)
      refute OauthToken.stale_or_expired?(token, 3)
    end

    test "handles token without expiration data" do
      recent_refresh = DateTime.add(DateTime.utc_now(), -30, :minute)

      token = %OauthToken{
        body: %{"access_token" => "token123"},
        updated_at: DateTime.utc_now(),
        last_refreshed: recent_refresh
      }

      refute OauthToken.stale_or_expired?(token, 1)
    end

    test "handles edge case of exactly max age" do
      future_time = System.system_time(:second) + 3600
      exactly_one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        updated_at: DateTime.utc_now(),
        last_refreshed: exactly_one_hour_ago
      }

      assert OauthToken.stale_or_expired?(token, 1)
    end

    test "handles malformed expiration data gracefully" do
      recent_refresh = DateTime.add(DateTime.utc_now(), -30, :minute)

      token = %OauthToken{
        body: %{"expires_at" => "not_a_number"},
        updated_at: DateTime.utc_now(),
        last_refreshed: recent_refresh
      }

      refute OauthToken.stale_or_expired?(token, 1)
    end
  end

  describe "age_in_hours/1" do
    test "returns nil for token that was never refreshed" do
      token = %OauthToken{last_refreshed: nil}
      assert OauthToken.age_in_hours(token) == nil
    end

    test "returns correct age in hours" do
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)
      token = %OauthToken{last_refreshed: two_hours_ago}
      assert OauthToken.age_in_hours(token) == 2
    end

    test "returns 0 for recently refreshed token" do
      recent = DateTime.add(DateTime.utc_now(), -30, :minute)
      token = %OauthToken{last_refreshed: recent}
      assert OauthToken.age_in_hours(token) == 0
    end

    test "returns 1 for token refreshed just over an hour ago" do
      one_hour_five_minutes_ago = DateTime.add(DateTime.utc_now(), -65, :minute)
      token = %OauthToken{last_refreshed: one_hour_five_minutes_ago}
      assert OauthToken.age_in_hours(token) == 1
    end

    test "returns correct age for older tokens" do
      twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24, :hour)
      token = %OauthToken{last_refreshed: twenty_four_hours_ago}
      assert OauthToken.age_in_hours(token) == 24
    end

    test "handles exact hour boundaries" do
      exactly_one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
      token = %OauthToken{last_refreshed: exactly_one_hour_ago}
      assert OauthToken.age_in_hours(token) == 1
    end

    test "handles very recent refresh (seconds ago)" do
      seconds_ago = DateTime.add(DateTime.utc_now(), -30, :second)
      token = %OauthToken{last_refreshed: seconds_ago}
      assert OauthToken.age_in_hours(token) == 0
    end

    test "handles very old tokens" do
      one_week_ago = DateTime.add(DateTime.utc_now(), -168, :hour)
      token = %OauthToken{last_refreshed: one_week_ago}
      assert OauthToken.age_in_hours(token) == 168
    end

    test "handles fractional hours correctly (rounds down)" do
      ninety_minutes_ago = DateTime.add(DateTime.utc_now(), -90, :minute)
      token = %OauthToken{last_refreshed: ninety_minutes_ago}
      assert OauthToken.age_in_hours(token) == 1
    end

    test "handles edge case of exactly now" do
      now = DateTime.utc_now()
      token = %OauthToken{last_refreshed: now}
      assert OauthToken.age_in_hours(token) == 0
    end
  end

  describe "extract_scopes/1" do
    test "delegates to OauthValidation.extract_scopes" do
      test_data = %{"scope" => "test scope"}
      result1 = OauthToken.extract_scopes(test_data)
      result2 = OauthValidation.extract_scopes(test_data)
      assert result1 == result2
    end

    test "extracts from string scope with space delimiter" do
      token_data = %{"scope" => "read write admin"}
      result = OauthToken.extract_scopes(token_data)
      assert {:ok, ["read", "write", "admin"]} = result
    end

    test "extracts from atom key scope" do
      token_data = %{scope: "read write"}
      result = OauthToken.extract_scopes(token_data)
      assert {:ok, ["read", "write"]} = result
    end

    test "extracts from scopes array with string key" do
      token_data = %{"scopes" => ["read", "write"]}
      result = OauthToken.extract_scopes(token_data)
      assert {:ok, ["read", "write"]} = result
    end

    test "extracts from scopes array with atom key" do
      token_data = %{scopes: ["read", "write"]}
      result = OauthToken.extract_scopes(token_data)
      assert {:ok, ["read", "write"]} = result
    end

    test "returns error for invalid format" do
      token_data = %{"access_token" => "token123"}
      result = OauthToken.extract_scopes(token_data)
      assert :error = result
    end

    test "handles single scope" do
      token_data = %{"scope" => "read"}
      result = OauthToken.extract_scopes(token_data)
      assert {:ok, ["read"]} = result
    end

    test "handles empty scope string" do
      token_data = %{"scope" => ""}
      result = OauthToken.extract_scopes(token_data)
      assert {:ok, []} = result
    end

    test "handles nil values" do
      result = OauthToken.extract_scopes(%{"scope" => nil})
      assert :error = result
    end

    test "handles non-string, non-list scope values" do
      result = OauthToken.extract_scopes(%{"scope" => 123})
      assert :error = result
    end

    test "handles empty map" do
      result = OauthToken.extract_scopes(%{})
      assert :error = result
    end

    test "handles nil input" do
      result = OauthToken.extract_scopes(nil)
      assert :error = result
    end

    test "consistency with different input formats" do
      string_format = %{"scope" => "read write admin"}
      array_format = %{"scopes" => ["read", "write", "admin"]}
      atom_string_format = %{scope: "read write admin"}
      atom_array_format = %{scopes: ["read", "write", "admin"]}

      {:ok, result1} = OauthToken.extract_scopes(string_format)
      {:ok, result2} = OauthToken.extract_scopes(array_format)
      {:ok, result3} = OauthToken.extract_scopes(atom_string_format)
      {:ok, result4} = OauthToken.extract_scopes(atom_array_format)

      assert result1 == ["read", "write", "admin"]
      assert result2 == ["read", "write", "admin"]
      assert result3 == ["read", "write", "admin"]
      assert result4 == ["read", "write", "admin"]
    end
  end

  describe "associations" do
    test "belongs to oauth_client" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      loaded_token = OauthToken |> preload(:oauth_client) |> Repo.get!(token.id)
      assert loaded_token.oauth_client.id == oauth_client.id
    end

    test "belongs to user" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      loaded_token = OauthToken |> preload(:user) |> Repo.get!(token.id)
      assert loaded_token.user.id == user.id
    end

    test "has one credential" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      credential =
        insert(:credential, %{
          user: user,
          oauth_token: token
        })

      loaded_token = OauthToken |> preload(:credential) |> Repo.get!(token.id)
      assert loaded_token.credential.id == credential.id
    end

    test "can load all associations together" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      credential =
        insert(:credential, %{
          user: user,
          oauth_token: token
        })

      loaded_token =
        OauthToken
        |> preload([:user, :oauth_client, :credential])
        |> Repo.get!(token.id)

      assert loaded_token.user.id == user.id
      assert loaded_token.oauth_client.id == oauth_client.id
      assert loaded_token.credential.id == credential.id
    end

    test "handles token without credential" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      loaded_token = OauthToken |> preload(:credential) |> Repo.get!(token.id)
      assert loaded_token.credential == nil
    end

    test "association constraints work correctly" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(valid_attrs)
      assert {:ok, _token} = Repo.insert(changeset)

      invalid_client_attrs = %{
        valid_attrs
        | oauth_client_id: Ecto.UUID.generate()
      }

      changeset = OauthToken.changeset(invalid_client_attrs)
      assert {:error, changeset} = Repo.insert(changeset)
      assert {"does not exist", _} = changeset.errors[:oauth_client]

      invalid_user_attrs = %{valid_attrs | user_id: Ecto.UUID.generate()}
      changeset = OauthToken.changeset(invalid_user_attrs)
      assert {:error, changeset} = Repo.insert(changeset)
      assert {"does not exist", _} = changeset.errors[:user]
    end

    test "can query tokens by user" do
      user1 = insert(:user)
      user2 = insert(:user)
      oauth_client = insert(:oauth_client)

      _token1 = insert(:oauth_token, %{user: user1, oauth_client: oauth_client})
      token2 = insert(:oauth_token, %{user: user2, oauth_client: oauth_client})
      _token3 = insert(:oauth_token, %{user: user1, oauth_client: oauth_client})

      user1_tokens = OauthToken |> where(user_id: ^user1.id) |> Repo.all()
      user2_tokens = OauthToken |> where(user_id: ^user2.id) |> Repo.all()

      assert length(user1_tokens) == 2
      assert length(user2_tokens) == 1
      assert hd(user2_tokens).id == token2.id
    end

    test "can query tokens by oauth_client" do
      user = insert(:user)
      oauth_client1 = insert(:oauth_client)
      oauth_client2 = insert(:oauth_client)

      token1 = insert(:oauth_token, %{user: user, oauth_client: oauth_client1})
      _token2 = insert(:oauth_token, %{user: user, oauth_client: oauth_client2})
      token3 = insert(:oauth_token, %{user: user, oauth_client: oauth_client1})

      client1_tokens =
        OauthToken |> where(oauth_client_id: ^oauth_client1.id) |> Repo.all()

      client2_tokens =
        OauthToken |> where(oauth_client_id: ^oauth_client2.id) |> Repo.all()

      assert length(client1_tokens) == 2
      assert length(client2_tokens) == 1

      client1_token_ids = Enum.map(client1_tokens, & &1.id) |> Enum.sort()
      expected_ids = [token1.id, token3.id] |> Enum.sort()
      assert client1_token_ids == expected_ids
    end
  end

  describe "encryption" do
    test "encrypts token body at rest" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body = %{
        "access_token" => "secret_access_token",
        "refresh_token" => "secret_refresh_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body,
          scopes: ["read"]
        })

      assert token.body == body

      persisted_body =
        from(t in OauthToken,
          select: type(t.body, :string),
          where: t.id == ^token.id
        )
        |> Repo.one!()

      refute persisted_body == body
    end

    test "decrypts token body when loaded" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body = %{
        "access_token" => "secret_token_123",
        "refresh_token" => "secret_refresh_123",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "read write"
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body,
          scopes: ["read", "write"]
        })

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == body
    end

    test "encrypts complex nested body structures" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      complex_body = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "user_info" => %{
          "id" => "user123",
          "name" => "Test User",
          "email" => "test@example.com"
        },
        "provider_data" => %{
          "provider" => "google",
          "account_id" => "google_account_123",
          "additional_fields" => ["field1", "field2"]
        }
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: complex_body,
          scopes: ["read", "write"]
        })

      persisted_body =
        from(t in OauthToken,
          select: type(t.body, :string),
          where: t.id == ^token.id
        )
        |> Repo.one!()

      refute persisted_body == complex_body

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == complex_body
    end

    test "handles empty body maps" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      empty_body = %{}

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: empty_body,
          scopes: []
        })

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == empty_body
    end

    test "encrypts sensitive data in token fields" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      sensitive_body = %{
        "access_token" => "very_secret_access_token_that_should_be_encrypted",
        "refresh_token" => "very_secret_refresh_token_that_should_be_encrypted",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write admin",
        "client_secret" => "super_secret_client_secret"
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: sensitive_body,
          scopes: ["read", "write", "admin"]
        })

      persisted_body =
        from(t in OauthToken,
          select: type(t.body, :string),
          where: t.id == ^token.id
        )
        |> Repo.one!()

      refute String.contains?(persisted_body, "very_secret_access_token")
      refute String.contains?(persisted_body, "very_secret_refresh_token")
      refute String.contains?(persisted_body, "super_secret_client_secret")

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == sensitive_body
    end

    test "encryption works with very large token bodies" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      large_body = %{
        "access_token" => String.duplicate("a", 1000),
        "refresh_token" => String.duplicate("b", 1000),
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "large_data" => String.duplicate("x", 5000),
        "metadata" => %{
          "nested_large_field" => String.duplicate("y", 2000)
        }
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: large_body,
          scopes: ["read", "write"]
        })

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == large_body
    end

    test "multiple tokens encrypt independently" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body1 = %{
        "access_token" => "token1_access",
        "refresh_token" => "token1_refresh",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      body2 = %{
        "access_token" => "token2_access",
        "refresh_token" => "token2_refresh",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "write admin"
      }

      token1 =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body1,
          scopes: ["read"]
        })

      token2 =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body2,
          scopes: ["write", "admin"]
        })

      reloaded_token1 = Repo.get!(OauthToken, token1.id)
      reloaded_token2 = Repo.get!(OauthToken, token2.id)

      assert reloaded_token1.body == body1
      assert reloaded_token2.body == body2
      refute reloaded_token1.body == reloaded_token2.body
    end
  end

  describe "virtual fields" do
    test "oauth_error_type and oauth_error_details are virtual" do
      token = %OauthToken{
        oauth_error_type: :missing_scopes,
        oauth_error_details: %{missing_scopes: ["write"]}
      }

      assert token.oauth_error_type == :missing_scopes
      assert token.oauth_error_details == %{missing_scopes: ["write"]}

      schema_fields = OauthToken.__schema__(:fields)
      refute :oauth_error_type in schema_fields
      refute :oauth_error_details in schema_fields
    end

    test "virtual fields are not persisted to database" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "token123",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          scopes: ["read"]
        })

      token_with_errors = %{
        token
        | oauth_error_type: :invalid_token_format,
          oauth_error_details: %{reason: "test error"}
      }

      assert token_with_errors.oauth_error_type == :invalid_token_format
      assert token_with_errors.oauth_error_details == %{reason: "test error"}

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.oauth_error_type == nil
      assert reloaded_token.oauth_error_details == nil
    end

    test "virtual fields can be set during changeset operations" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      invalid_attrs = %{
        body: %{
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(invalid_attrs)

      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]

      assert get_change(changeset, :oauth_error_type) == :missing_access_token
    end

    test "virtual fields maintain type information" do
      token = %OauthToken{
        oauth_error_type: :missing_refresh_token,
        oauth_error_details: %{
          expected_fields: ["refresh_token"],
          provided_fields: ["access_token", "expires_in"]
        }
      }

      assert is_atom(token.oauth_error_type)

      assert is_map(token.oauth_error_details)
      assert token.oauth_error_details.expected_fields == ["refresh_token"]

      assert token.oauth_error_details.provided_fields == [
               "access_token",
               "expires_in"
             ]
    end

    test "virtual fields can hold various error types" do
      error_scenarios = [
        {:missing_scopes, %{missing_scopes: ["write", "admin"]}},
        {:invalid_token_format,
         %{received_type: "string", expected_type: "map"}},
        {:missing_access_token, %{field: "access_token"}},
        {:unsupported_token_type, %{received: "Basic", expected: "Bearer"}}
      ]

      for {error_type, error_details} <- error_scenarios do
        token = %OauthToken{
          oauth_error_type: error_type,
          oauth_error_details: error_details
        }

        assert token.oauth_error_type == error_type
        assert token.oauth_error_details == error_details
      end
    end

    test "virtual fields can be nil" do
      token = %OauthToken{
        oauth_error_type: nil,
        oauth_error_details: nil
      }

      assert token.oauth_error_type == nil
      assert token.oauth_error_details == nil
    end

    test "struct can be created without virtual fields" do
      token = %OauthToken{
        body: %{"access_token" => "token123"},
        scopes: ["read"]
      }

      assert token.oauth_error_type == nil
      assert token.oauth_error_details == nil
    end
  end

  describe "edge cases" do
    test "handles very large token bodies" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      large_body = %{
        "access_token" => String.duplicate("a", 1000),
        "refresh_token" => String.duplicate("b", 1000),
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "extra_data" => String.duplicate("c", 5000)
      }

      attrs = %{
        body: large_body,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles token body with extra fields" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_extras = %{
        "access_token" => "token_123",
        "refresh_token" => "refresh_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "custom_field" => "custom_value",
        "nested" => %{"data" => "value"},
        "provider_specific" => %{
          "google_data" => "some_value",
          "metadata" => ["item1", "item2"]
        }
      }

      attrs = %{
        body: body_with_extras,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles token with deeply nested structures" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      deeply_nested_body = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read",
        "user_data" => %{
          "profile" => %{
            "personal" => %{
              "name" => "Test User",
              "details" => %{
                "preferences" => %{
                  "theme" => "dark",
                  "notifications" => %{
                    "email" => true,
                    "push" => false
                  }
                }
              }
            }
          }
        }
      }

      attrs = %{
        body: deeply_nested_body,
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles token with array values in body" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_arrays = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scopes" => ["read", "write", "admin"],
        "permissions" => ["user:read", "user:write"],
        "features" => ["feature1", "feature2", "feature3"],
        "metadata" => %{
          "tags" => ["tag1", "tag2"],
          "categories" => ["cat1", "cat2"]
        }
      }

      attrs = %{
        body: body_with_arrays,
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]
    end

    test "handles token with numeric values as strings" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_string_numbers = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => "3600",
        "scope" => "read",
        "user_id" => "12345",
        "timestamp" => "1234567890"
      }

      attrs = %{
        body: body_with_string_numbers,
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles empty and whitespace-only scopes gracefully" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read   write      admin"
        },
        scopes: ["read", "", "  ", "write", "admin"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]
    end

    test "handles tokens with zero or negative expiration times" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs_zero = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 0,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs_zero)
      refute changeset.valid?

      attrs_negative = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => -300,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs_negative)
      refute changeset.valid?
    end

    test "handles tokens with boolean and null values" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_mixed_types = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read",
        "is_active" => true,
        "is_expired" => false,
        "optional_field" => nil,
        "metadata" => %{
          "has_refresh" => true,
          "null_field" => nil
        }
      }

      attrs = %{
        body: body_with_mixed_types,
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles extremely long scope names" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      very_long_scope = String.duplicate("verylongscope", 100)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read #{very_long_scope} write"
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?

      scopes = get_change(changeset, :scopes)
      assert "read" in scopes
      assert very_long_scope in scopes
      assert "write" in scopes
    end

    test "handles tokens with unicode and special characters" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      unicode_body = %{
        "access_token" => "tøken123_ñoñó",
        "refresh_token" => "refrësh123_测试",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "user_name" => "Test Üser 测试用户",
        "description" => "Token with émojis 🔐🔑"
      }

      attrs = %{
        body: unicode_body,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end
  end

  describe "integration with OauthValidation" do
    test "validates complete OAuth 2.0 compliance" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_attrs = %{
        body: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(valid_attrs)
      assert changeset.valid?

      invalid_attrs = %{
        body: %{
          "access_token" => "token123"
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(invalid_attrs)
      refute changeset.valid?
    end

    test "populates error details from OauthValidation" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]

      assert get_change(changeset, :oauth_error_type) == :missing_access_token
    end

    test "validates scope formats consistently with OauthValidation" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs_string = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write admin"
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs_string)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]

      attrs_array = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scopes" => ["read", "write", "admin"]
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs_array)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]
    end

    test "delegates all validation to OauthValidation module" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      validation_scenarios = [
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          true,
          "Valid complete token"
        },
        {
          %{
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Missing access_token"
        },
        {
          %{
            "access_token" => "token",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Missing refresh_token"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Missing token_type"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Basic",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Invalid token_type"
        },
        {
          %{
            "access_token" => "",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Empty access_token"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 0,
            "scope" => "read"
          },
          false,
          "Zero expires_in"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "scope" => ""
          },
          false,
          "Empty scope"
        }
      ]

      for {body, should_be_valid, description} <- validation_scenarios do
        attrs = %{
          body: body,
          oauth_client_id: oauth_client.id,
          user_id: user.id
        }

        changeset = OauthToken.changeset(attrs)

        if should_be_valid do
          assert changeset.valid?, "#{description} should be valid"
        else
          refute changeset.valid?, "#{description} should be invalid"
        end
      end
    end

    test "error handling matches OauthValidation error types" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      error_test_cases = [
        {
          %{"invalid" => "token"},
          :missing_access_token,
          "Invalid token format should trigger missing_access_token"
        },
        {
          %{
            "access_token" => "",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          :invalid_access_token,
          "Empty access_token should trigger invalid_access_token"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Basic",
            "expires_in" => 3600,
            "scope" => "read"
          },
          :unsupported_token_type,
          "Wrong token_type should trigger unsupported_token_type"
        }
      ]

      for {body, expected_error_type, description} <- error_test_cases do
        attrs = %{
          body: body,
          oauth_client_id: oauth_client.id,
          user_id: user.id
        }

        changeset = OauthToken.changeset(attrs)
        refute changeset.valid?, description

        assert get_change(changeset, :oauth_error_type) == expected_error_type,
               "#{description} - Expected error type #{expected_error_type}"
      end
    end

    test "scope extraction uses OauthValidation consistently" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      scope_test_cases = [
        {%{"scope" => "read write admin"}, ["read", "write", "admin"]},
        {%{scope: "read write"}, ["read", "write"]},
        {%{"scopes" => ["read", "write"]}, ["read", "write"]},
        {%{scopes: ["admin"]}, ["admin"]},
        {%{"scope" => "  read   write  "}, ["read", "write"]},
        {%{"scope" => ""}, []}
      ]

      for {body_scope_data, expected_scopes} <- scope_test_cases do
        body =
          Map.merge(
            %{
              "access_token" => "token123",
              "refresh_token" => "refresh123",
              "token_type" => "Bearer",
              "expires_in" => 3600
            },
            body_scope_data
          )

        attrs = %{
          body: body,
          oauth_client_id: oauth_client.id,
          user_id: user.id
        }

        changeset = OauthToken.changeset(attrs)

        if expected_scopes == [] and body_scope_data == %{"scope" => ""} do
          refute changeset.valid?
        else
          assert changeset.valid?
          assert get_change(changeset, :scopes) == expected_scopes
        end
      end
    end

    test "extract_scopes delegates properly to OauthValidation" do
      test_cases = [
        {%{"scope" => "read write"}, {:ok, ["read", "write"]}},
        {%{scope: "admin"}, {:ok, ["admin"]}},
        {%{"scopes" => ["read", "admin"]}, {:ok, ["read", "admin"]}},
        {%{scopes: ["write"]}, {:ok, ["write"]}},
        {%{"invalid" => "data"}, :error},
        {%{}, :error}
      ]

      for {input, expected_result} <- test_cases do
        oauth_token_result = OauthToken.extract_scopes(input)
        oauth_validation_result = OauthValidation.extract_scopes(input)

        assert oauth_token_result == oauth_validation_result
        assert oauth_token_result == expected_result
      end
    end

    test "token validation in valid?/1 uses OauthValidation" do
      valid_token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        updated_at: DateTime.add(DateTime.utc_now(), -1800, :second)
      }

      assert OauthToken.valid?(valid_token)

      invalid_token = %OauthToken{
        body: %{
          "access_token" => "token123"
        },
        updated_at: DateTime.utc_now()
      }

      refute OauthToken.valid?(invalid_token)

      expired_token = %OauthToken{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        updated_at: DateTime.add(DateTime.utc_now(), -7200, :second)
      }

      refute OauthToken.valid?(expired_token)
    end

    test "update_token_changeset validates with OauthValidation" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "old_token",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          }
        )

      valid_update = %{
        "access_token" => "new_token",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "read write"
      }

      changeset = OauthToken.update_token_changeset(token, valid_update)
      assert changeset.valid?

      invalid_update = %{
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "read write"
      }

      changeset = OauthToken.update_token_changeset(token, invalid_update)
      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]
    end
  end

  describe "last_refreshed functionality" do
    test "update_token_changeset sets last_refreshed to current time" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "old_token",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          last_refreshed: DateTime.add(DateTime.utc_now(), -1, :hour)
        )

      new_token_data = %{
        "access_token" => "new_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)

      assert changeset.valid?
      new_last_refreshed = get_change(changeset, :last_refreshed)
      assert new_last_refreshed != nil

      age_seconds =
        DateTime.diff(DateTime.utc_now(), new_last_refreshed, :second)

      assert age_seconds < 60
    end

    test "can manually set last_refreshed in changeset" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      specific_time =
        DateTime.add(DateTime.utc_now(), -2, :hour) |> DateTime.truncate(:second)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: specific_time
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
      assert get_change(changeset, :last_refreshed) == specific_time
    end
  end

  describe "scope normalization (tested through public interface)" do
    test "normalizes scopes to lowercase through changeset" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "READ Write ADMIN"
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]
    end

    test "handles mixed case scopes in explicit scopes field" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write admin"
        },
        scopes: ["READ", "Write", " ADMIN "],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]
    end

    test "removes empty strings and trims whitespace through changeset" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "  read   write    admin  "
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["read", "write", "admin"]
    end

    test "handles scopes with special characters through changeset" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "user:read user:write ADMIN:ALL"
        },
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?

      expected_scopes = ["user:read", "user:write", "admin:all"]
      assert get_change(changeset, :scopes) == expected_scopes
    end

    test "preserves order while removing duplicates through update" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "old_token",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          }
        )

      new_token_data = %{
        "access_token" => "new_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "admin read write admin"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)
      assert changeset.valid?
      assert get_change(changeset, :scopes) == ["admin", "read", "write"]
    end
  end
end
