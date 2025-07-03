defmodule Lightning.Credentials.OauthValidationTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.OauthValidation
  alias Lightning.Credentials.OauthValidation.Error
  alias Lightning.Credentials.OauthToken

  describe "Error struct" do
    test "creates error with type, message, and details" do
      error = Error.new(:missing_scopes, "Test message", %{test: "data"})

      assert error.type == :missing_scopes
      assert error.message == "Test message"
      assert error.details == %{test: "data"}
    end

    test "creates error without details" do
      error = Error.new(:invalid_token_format, "Test message")

      assert error.type == :invalid_token_format
      assert error.message == "Test message"
      assert error.details == nil
    end
  end

  describe "validate_token_data/1" do
    test "validates complete valid token data with Bearer token type" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "validates token with expires_at instead of expires_in" do
      current_time = System.system_time(:second)
      future_time = current_time + 3600

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_at" => future_time,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "validates token with ISO 8601 expires_at" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_at" => "2024-12-31T23:59:59Z",
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "validates token with scopes array instead of scope string" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scopes" => ["read", "write"]
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "validates token with atom keys" do
      token_data = %{
        access_token: "access_token_123",
        refresh_token: "refresh_token_123",
        token_type: "Bearer",
        expires_in: 3600,
        scope: "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "accepts case-insensitive Bearer token type" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "rejects invalid token format" do
      result = OauthValidation.validate_token_data("invalid_token")

      assert {:error, %Error{type: :invalid_token_format, message: message}} =
               result

      assert message == "OAuth token must be a valid map"
    end

    test "rejects token without access_token" do
      token_data = %{
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_access_token, message: message}} =
               result

      assert message == "Missing required OAuth field: access_token"
    end

    test "rejects empty access_token" do
      token_data = %{
        "access_token" => "",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_access_token, message: message}} =
               result

      assert message == "access_token cannot be empty"
    end

    test "rejects non-string access_token" do
      token_data = %{
        "access_token" => 123,
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_access_token, message: message}} =
               result

      assert String.contains?(message, "access_token must be a non-empty string")
    end

    test "rejects token without refresh_token" do
      token_data = %{
        "access_token" => "access_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_refresh_token, message: message}} =
               result

      assert message == "Missing required OAuth field: refresh_token"
    end

    test "rejects empty refresh_token" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_refresh_token, message: message}} =
               result

      assert message == "refresh_token cannot be empty"
    end

    test "rejects token without token_type" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_token_type, message: message}} =
               result

      assert message == "Missing required OAuth field: token_type"
    end

    test "rejects unsupported token_type" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Basic",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :unsupported_token_type, message: message}} =
               result

      assert message == "Unsupported token type: 'Basic'. Expected 'Bearer'"
    end

    test "rejects token without scope or scopes" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_scope, message: message}} = result
      assert message == "Missing required OAuth field: scope or scopes"
    end

    test "rejects empty scope string" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => ""
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_scope, message: message}} = result
      assert message == "scope field cannot be empty"
    end

    test "rejects empty scopes array" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scopes" => []
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_scope, message: message}} = result
      assert message == "scopes array cannot be empty"
    end

    test "rejects scopes array with non-strings" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scopes" => ["read", 123, "write"]
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_oauth_response, message: message}} =
               result

      assert message == "scopes array must contain only strings"
    end

    test "rejects token without expiration fields" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_expiration, message: message}} =
               result

      assert message ==
               "Missing expiration field: either expires_in or expires_at is required"
    end

    test "rejects invalid expires_in values" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 0,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_expiration}} = result

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => -300,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_expiration}} = result

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 999_999_999,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_expiration}} = result
    end

    test "accepts expires_in as string" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => "3600",
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "rejects invalid expires_in string" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => "not_a_number",
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_expiration}} = result
    end

    test "rejects expires_at too far in past" do
      past_time = System.system_time(:second) - 2 * 24 * 3600

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_at" => past_time,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_expiration}} = result
    end

    test "rejects expires_at too far in future" do
      future_time = System.system_time(:second) + 2 * 365 * 24 * 3600

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_at" => future_time,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_expiration}} = result
    end

    test "accepts expires_at as Unix timestamp string" do
      future_time = System.system_time(:second) + 3600
      timestamp_string = Integer.to_string(future_time)

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_at" => timestamp_string,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "validates nested map normalization" do
      token_data = %{
        access_token: "token123",
        refresh_token: "refresh123",
        token_type: "Bearer",
        expires_in: 3600,
        scope: "read",
        user_info: %{
          name: "Test User",
          id: 12345
        }
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "handles nil token data" do
      result = OauthValidation.validate_token_data(nil)

      assert {:error, %Error{type: :invalid_token_format}} = result
    end

    test "handles empty map" do
      result = OauthValidation.validate_token_data(%{})

      assert {:error, %Error{type: :missing_access_token}} = result
    end
  end

  describe "validate_scope_grant/2" do
    test "succeeds when all expected scopes are granted" do
      token_data = %{"scope" => "read write admin"}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "succeeds with exact scope match" do
      token_data = %{"scope" => "read write"}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "succeeds with empty expected scopes" do
      token_data = %{"scope" => "read write"}
      expected_scopes = []

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "succeeds with case-insensitive scope matching" do
      token_data = %{"scope" => "READ write ADMIN"}
      expected_scopes = ["read", "Write", "admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "works with scopes array" do
      token_data = %{"scopes" => ["read", "write", "admin"]}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "works with atom keys" do
      token_data = %{scope: "read write admin"}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "fails when some scopes are missing" do
      token_data = %{"scope" => "read"}
      expected_scopes = ["read", "write", "admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error,
              %Error{type: :missing_scopes, details: details, message: message}} =
               result

      assert details.missing_scopes == ["write", "admin"]
      assert details.granted_scopes == ["read"]
      assert details.expected_scopes == ["read", "write", "admin"]

      assert message ==
               "Missing required scopes: write, admin. Please reauthorize and grant all selected permissions."
    end

    test "preserves original case in error messages" do
      token_data = %{"scope" => "read"}
      expected_scopes = ["read", "WRITE", "Admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error,
              %Error{type: :missing_scopes, details: details, message: message}} =
               result

      assert details.missing_scopes == ["WRITE", "Admin"]

      assert message ==
               "Missing required scopes: WRITE, Admin. Please reauthorize and grant all selected permissions."
    end

    test "fails when token has no scope data" do
      token_data = %{"access_token" => "token123"}
      expected_scopes = ["read"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error, %Error{type: :invalid_oauth_response, message: message}} =
               result

      assert message == "OAuth token missing scope information"
    end

    test "handles empty scope string" do
      token_data = %{"scope" => ""}
      expected_scopes = ["read"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error, %Error{type: :missing_scopes}} = result
    end

    test "handles scope string with extra whitespace" do
      token_data = %{"scope" => "  read   write  "}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "handles malformed scope strings gracefully" do
      token_data = %{"scope" => "   read    write   admin   "}
      expected_scopes = ["read", "write", "admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "handles duplicate scopes in grant" do
      token_data = %{"scope" => "read read write write"}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end
  end

  describe "extract_scopes/1" do
    test "extracts from string scope with space delimiter" do
      token_data = %{"scope" => "read write admin"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write", "admin"]} = result
    end

    test "extracts from atom key scope" do
      token_data = %{scope: "read write"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "extracts from scopes array with string key" do
      token_data = %{"scopes" => ["read", "write"]}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "extracts from scopes array with atom key" do
      token_data = %{scopes: ["read", "write"]}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "handles scopes array with non-string values" do
      token_data = %{"scopes" => ["read", 123, "write", nil]}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "handles scope string with multiple whitespace" do
      token_data = %{"scope" => "read    write   admin"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write", "admin"]} = result
    end

    test "returns error for invalid format" do
      token_data = %{"access_token" => "token123"}

      result = OauthValidation.extract_scopes(token_data)

      assert :error = result
    end

    test "handles single scope" do
      token_data = %{"scope" => "read"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read"]} = result
    end

    test "handles empty scope string" do
      token_data = %{"scope" => ""}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, []} = result
    end

    test "handles nil values" do
      result = OauthValidation.extract_scopes(%{"scope" => nil})

      assert :error = result
    end

    test "handles non-string, non-list scope values" do
      result = OauthValidation.extract_scopes(%{"scope" => 123})

      assert :error = result
    end
  end

  describe "normalize_scopes/2" do
    test "normalizes nil to empty list" do
      result = OauthValidation.normalize_scopes(nil)

      assert [] = result
    end

    test "normalizes string with space delimiter" do
      result = OauthValidation.normalize_scopes("READ Write ADMIN")

      assert ["read", "write", "admin"] = result
    end

    test "normalizes string with custom delimiter" do
      result = OauthValidation.normalize_scopes("read,write,admin", ",")

      assert ["read", "write", "admin"] = result
    end

    test "normalizes OauthToken struct" do
      token = %OauthToken{body: %{"scope" => "READ Write"}}

      result = OauthValidation.normalize_scopes(token)

      assert ["read", "write"] = result
    end

    test "normalizes OauthToken struct with scopes key" do
      token = %OauthToken{body: %{"scopes" => ["READ", "Write"]}}

      result = OauthValidation.normalize_scopes(token)

      assert ["read", "write"] = result
    end

    test "handles token without scope in body" do
      token = %OauthToken{body: %{"access_token" => "token123"}}

      result = OauthValidation.normalize_scopes(token)

      assert [] = result
    end

    test "handles token with nil body" do
      token = %OauthToken{body: nil}

      result = OauthValidation.normalize_scopes(token)

      assert [] = result
    end

    test "handles token with non-map body" do
      token = %OauthToken{body: "not_a_map"}

      result = OauthValidation.normalize_scopes(token)

      assert [] = result
    end

    test "handles list of scopes" do
      result = OauthValidation.normalize_scopes(["READ", "Write", " ADMIN "])

      assert ["read", "write", "admin"] = result
    end

    test "handles atom scope" do
      result = OauthValidation.normalize_scopes(:read)

      assert ["read"] = result
    end

    test "handles mixed list with atoms and strings" do
      result = OauthValidation.normalize_scopes([:read, "WRITE", " admin "])

      assert ["read", "write", "admin"] = result
    end

    test "handles list with nil and invalid values" do
      result = OauthValidation.normalize_scopes(["read", nil, 123, "write", ""])

      assert ["read", "write"] = result
    end

    test "handles integer input gracefully" do
      result = OauthValidation.normalize_scopes(123)

      assert [] = result
    end

    test "handles map input (non-OauthToken)" do
      result = OauthValidation.normalize_scopes(%{scope: "read write"})

      assert [] = result
    end

    test "removes empty strings and trims whitespace" do
      result = OauthValidation.normalize_scopes("  read   write  ")

      assert ["read", "write"] = result
    end

    test "handles empty string" do
      result = OauthValidation.normalize_scopes("")

      assert [] = result
    end

    test "handles string with only whitespace" do
      result = OauthValidation.normalize_scopes("   ")

      assert [] = result
    end

    test "removes duplicates" do
      result = OauthValidation.normalize_scopes("read write read admin write")

      assert ["read", "write", "admin"] = result
    end

    test "handles different delimiters" do
      assert ["read", "write"] =
               OauthValidation.normalize_scopes("read|write", "|")

      assert ["read", "write"] =
               OauthValidation.normalize_scopes("read;write", ";")

      assert ["read", "write"] =
               OauthValidation.normalize_scopes("read\twrite", "\t")
    end

    test "handles empty list" do
      result = OauthValidation.normalize_scopes([])

      assert [] = result
    end
  end

  describe "integration scenarios" do
    test "complete OAuth validation flow with Bearer token" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "profile email read write"
      }

      requested_scopes = ["profile", "email", "read"]

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      assert :ok =
               OauthValidation.validate_scope_grant(token_data, requested_scopes)

      assert {:ok, granted_scopes} = OauthValidation.extract_scopes(token_data)
      assert "profile" in granted_scopes
      assert "email" in granted_scopes
      assert "read" in granted_scopes
      assert "write" in granted_scopes
    end

    test "validation fails for insufficient scopes" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "profile email"
      }

      requested_scopes = ["profile", "email", "read"]

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_scopes, details: details}} =
               OauthValidation.validate_scope_grant(token_data, requested_scopes)

      assert details.missing_scopes == ["read"]
      assert details.granted_scopes == ["profile", "email"]
      assert details.expected_scopes == ["profile", "email", "read"]
    end

    test "handles mixed format inputs with case-insensitive scopes" do
      token_data = %{
        access_token: "token123",
        refresh_token: "refresh123",
        token_type: "Bearer",
        expires_in: 3600,
        scope: "READ Write ADMIN"
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      expected_scopes = ["read", "write"]

      assert :ok =
               OauthValidation.validate_scope_grant(token_data, expected_scopes)
    end

    test "complete flow with expires_at timestamp" do
      future_time = System.system_time(:second) + 7200

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_at" => future_time,
        "scopes" => ["read", "write", "admin"]
      }

      requested_scopes = ["read", "write"]

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      assert :ok =
               OauthValidation.validate_scope_grant(token_data, requested_scopes)

      assert {:ok, granted_scopes} = OauthValidation.extract_scopes(token_data)
      assert "read" in granted_scopes
      assert "write" in granted_scopes
      assert "admin" in granted_scopes
    end
  end

  describe "edge cases and error handling" do
    test "handles very long scope strings" do
      long_scope = String.duplicate("verylongscope", 100)
      token_data = %{"scope" => long_scope}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, [^long_scope]} = result
    end

    test "handles many scopes in string" do
      many_scopes = Enum.join(1..1000 |> Enum.map(&"scope#{&1}"), " ")
      token_data = %{"scope" => many_scopes}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, scopes} = result
      assert length(scopes) == 1000
    end

    test "validates token with minimal required fields" do
      token_data = %{
        "access_token" => "a",
        "refresh_token" => "r",
        "token_type" => "Bearer",
        "expires_in" => 1,
        "scope" => "s"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "handles mixed case in scope validation with case-insensitive matching" do
      token_data = %{"scope" => "READ write ADMIN"}
      expected_scopes = ["read", "WRITE", "admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "scope normalization handles edge cases" do
      assert [] = OauthValidation.normalize_scopes(nil)
      assert [] = OauthValidation.normalize_scopes("")
      assert [] = OauthValidation.normalize_scopes("   ")
      assert ["test"] = OauthValidation.normalize_scopes("TEST")
      assert ["a", "b"] = OauthValidation.normalize_scopes("A   B   ")
    end

    test "validates error message formatting for missing scopes" do
      token_data = %{"scope" => "read"}
      expected_scopes = ["read", "write", "admin", "delete"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error, %Error{message: message}} = result

      assert message ==
               "Missing required scopes: write, admin, delete. Please reauthorize and grant all selected permissions."
    end

    test "handles token with both expires_in and expires_at (expires_in takes precedence)" do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "expires_at" => System.system_time(:second) + 7200,
        "scope" => "read write"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "handles whitespace-only scopes in arrays" do
      token_data = %{"scopes" => ["read", "  ", "write", ""]}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "validates reasonable bounds for expires_in" do
      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_in" => 1,
        "scope" => "read"
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      max_valid = 365 * 24 * 3600 - 1

      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_in" => max_valid,
        "scope" => "read"
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)
    end

    test "validates clock skew tolerance for expires_at" do
      past_time = System.system_time(:second) - 23 * 3600

      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_at" => past_time,
        "scope" => "read"
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)
    end

    test "handles atom conversion errors gracefully" do
      result = OauthValidation.normalize_scopes([:read, :valid_atom])

      assert ["read", "valid_atom"] = result
    end
  end

  describe "private function behavior via public API" do
    test "normalize_keys is applied during validation" do
      token_data = %{
        access_token: "token",
        refresh_token: "refresh",
        token_type: "Bearer",
        expires_in: 3600,
        scope: "read"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:ok, ^token_data} = result
    end

    test "validation pipeline stops at first error" do
      token_data = %{}

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_access_token}} = result
    end

    test "expiration validation accepts both field types" do
      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "scope" => "read",
        "expires_in" => 3600
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      future_time = System.system_time(:second) + 3600

      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "scope" => "read",
        "expires_at" => future_time
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)
    end

    test "scope extraction and validation consistency" do
      token_data = %{"scope" => "read write admin"}

      assert {:ok, extracted} = OauthValidation.extract_scopes(token_data)
      assert extracted == ["read", "write", "admin"]

      assert :ok =
               OauthValidation.validate_scope_grant(token_data, ["read", "write"])

      token_data = %{"scopes" => ["read", "write", "admin"]}

      assert {:ok, extracted} = OauthValidation.extract_scopes(token_data)
      assert extracted == ["read", "write", "admin"]

      assert :ok =
               OauthValidation.validate_scope_grant(token_data, ["read", "write"])
    end

    test "case-insensitive scope matching preserves original case in errors" do
      token_data = %{"scope" => "read PROFILE"}
      expected_scopes = ["Read", "PROFILE", "Admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error, %Error{type: :missing_scopes, details: details}} = result

      assert details.missing_scopes == ["Admin"]
      assert details.granted_scopes == ["read", "PROFILE"]
      assert details.expected_scopes == ["Read", "PROFILE", "Admin"]
    end
  end

  describe "new validation features" do
    test "validates token_type field is present and correct" do
      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "expires_in" => 3600,
        "scope" => "read"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_token_type}} = result

      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Basic",
        "expires_in" => 3600,
        "scope" => "read"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :unsupported_token_type}} = result
    end

    test "validates token and scope values are non-empty" do
      token_data = %{
        "access_token" => "",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_access_token}} = result

      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => ""
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :missing_scope}} = result
    end

    test "validates expiration bounds and formats" do
      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_in" => "3600",
        "scope" => "read"
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      future_time = System.system_time(:second) + 3600
      timestamp_str = Integer.to_string(future_time)

      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_at" => timestamp_str,
        "scope" => "read"
      }

      assert {:ok, ^token_data} = OauthValidation.validate_token_data(token_data)

      token_data = %{
        "access_token" => "token",
        "refresh_token" => "refresh",
        "token_type" => "Bearer",
        "expires_in" => "not_a_number",
        "scope" => "read"
      }

      result = OauthValidation.validate_token_data(token_data)

      assert {:error, %Error{type: :invalid_expiration}} = result
    end

    test "improved scope parsing handles multiple whitespace" do
      token_data = %{"scope" => "read    write\t\tadmin\n\nprofile"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write", "admin", "profile"]} = result
    end
  end
end
