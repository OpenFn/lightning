defmodule Lightning.ScrubberTest do
  use ExUnit.Case, async: true

  alias Lightning.Credentials
  alias Lightning.Scrubber

  describe "scrub/2" do
    test "with no samples or an empty string" do
      scrubber = start_supervised!(Lightning.Scrubber)
      assert Scrubber.scrub(scrubber, "foo bar") == "foo bar"
      assert Scrubber.scrub(scrubber, nil) == nil
    end

    test "when using a name registration" do
      start_supervised!({Lightning.Scrubber, name: :bar})
      assert Scrubber.scrub(:bar, "foo bar") == "foo bar"
    end

    test "replaces secrets in string with ***" do
      secrets = ["23", "taylor@openfn.org", "funpass000"]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})

      scrubbed =
        scrubber
        |> Scrubber.scrub([
          "Successfully logged in as taylor@openfn.org using funpass000"
        ])

      assert scrubbed == ["Successfully logged in as *** using ***"]
    end

    test "doesn't put *** between every character when given an empty string secret" do
      secrets = ["123", ""]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})
      scrubbed = Scrubber.scrub(scrubber, ["Hello world, 123 is my password"])
      assert scrubbed == ["Hello world, *** is my password"]
    end

    test "doesn't replace booleans with ***" do
      secrets = ["ip_addr", "db_name", "my_user", "my_password", 5432, false]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})

      scrubbed =
        scrubber
        |> Scrubber.scrub([
          "Connected to ip_addr with enforce SSL set to false"
        ])

      assert scrubbed == ["Connected to *** with enforce SSL set to false"]
    end

    test "replaces Base64 encoded secrets in string with ***" do
      secrets = ["23", "taylor@openfn.org", "funpass000"]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})

      auth = Base.encode64("taylor@openfn.org:funpass000")

      scrubbed =
        scrubber
        |> Scrubber.scrub(
          "request headers: { authentication: '#{auth}', content-type: 'whatever' }"
        )

      assert scrubbed ==
               "request headers: { authentication: '***', content-type: 'whatever' }"
    end

    test "doesn't be hack itself by exposing longer secrets via shorter ones" do
      secrets = ["a", "secretpassword"]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})

      scrubbed =
        scrubber
        |> Scrubber.scrub("The password is secretpassword")

      assert scrubbed == "The p***ssword is ***"
    end

    test "scrubs multi-line strings by processing line-by-line" do
      secrets = ["my-secret-key", "sensitive-value", "12345"]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})

      # Simulate what dataclip_scrubber does: split by newline, scrub, rejoin
      multi_line_string = """
      Line 1 contains my-secret-key in the middle
      Line 2 has sensitive-value and also 12345
      Line 3 is clean
      Line 4 has my-secret-key again
      """

      scrubbed =
        multi_line_string
        |> String.split("\n")
        |> then(&Scrubber.scrub(scrubber, &1))
        |> Enum.join("\n")

      expected = """
      Line 1 contains *** in the middle
      Line 2 has *** and also ***
      Line 3 is clean
      Line 4 has *** again
      """

      assert scrubbed == expected
    end

    test "handles large multi-line JSON-like strings efficiently" do
      secrets = ["secret-token-abc123", "api-key-xyz789"]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})

      # Simulate a large JSON dataclip body
      large_json = """
      {
        "data": {
          "authentication": "secret-token-abc123",
          "nested": {
            "apiKey": "api-key-xyz789",
            "public": "this-is-fine"
          },
          "array": [
            {"token": "secret-token-abc123"},
            {"value": "safe-value"}
          ]
        }
      }
      """

      scrubbed =
        large_json
        |> String.split("\n")
        |> then(&Scrubber.scrub(scrubber, &1))
        |> Enum.join("\n")

      assert scrubbed =~ ~s("authentication": "***")
      assert scrubbed =~ ~s("apiKey": "***")
      assert scrubbed =~ ~s("token": "***")
      assert scrubbed =~ ~s("public": "this-is-fine")
      assert scrubbed =~ ~s("value": "safe-value")
      refute scrubbed =~ "secret-token-abc123"
      refute scrubbed =~ "api-key-xyz789"
    end
  end

  describe "add_samples/3" do
    test "updates the scrubber samples" do
      secrets = ["secretpassword"]
      basic_auth1 = Base.encode64("quux:secretpassword")

      scrubber =
        start_supervised!(
          {Lightning.Scrubber, samples: secrets, basic_auth: [basic_auth1]}
        )

      assert Scrubber.samples(scrubber) ==
               [
                 "c2VjcmV0cGFzc3dvcmQ6c2VjcmV0cGFzc3dvcmQ=",
                 basic_auth1,
                 "c2VjcmV0cGFzc3dvcmQ=",
                 "secretpassword"
               ]

      basic_auth2 = Base.encode64("quux:imasecret")

      assert :ok = Scrubber.add_samples(scrubber, ["imasecret"], [basic_auth2])

      assert Scrubber.samples(scrubber) ==
               [
                 "c2VjcmV0cGFzc3dvcmQ6c2VjcmV0cGFzc3dvcmQ=",
                 basic_auth1,
                 "aW1hc2VjcmV0OmltYXNlY3JldA==",
                 "c2VjcmV0cGFzc3dvcmQ=",
                 basic_auth2,
                 "secretpassword",
                 "aW1hc2VjcmV0",
                 "imasecret"
               ]
    end
  end

  describe "encode_samples/3" do
    test "creates base64 pairs of all samples as strings and adds them to the initial samples" do
      secrets = ["a", "secretpassword", 5432, false]

      assert Scrubber.encode_samples(secrets) == [
               "c2VjcmV0cGFzc3dvcmQ6c2VjcmV0cGFzc3dvcmQ=",
               "c2VjcmV0cGFzc3dvcmQ6NTQzMg==",
               "NTQzMjpzZWNyZXRwYXNzd29yZA==",
               "YTpzZWNyZXRwYXNzd29yZA==",
               "c2VjcmV0cGFzc3dvcmQ6YQ==",
               "c2VjcmV0cGFzc3dvcmQ=",
               "secretpassword",
               "NTQzMjo1NDMy",
               "YTo1NDMy",
               "NTQzMjph",
               "NTQzMg==",
               "5432",
               "YTph",
               "YQ==",
               "a"
             ]
    end

    test "adds basic auth base64 composed with usernames" do
      secrets = ["a", "secretpassword", 5432, false]

      credential = %Lightning.Credentials.Credential{
        schema: "raw",
        credential_bodies: [
          %Lightning.Credentials.CredentialBody{
            name: "main",
            body: %{
              "username" => "someuser",
              "email" => "user@email.com",
              "password" => "secretpassword"
            }
          }
        ]
      }

      basic_auth = Credentials.basic_auth_for(credential, "main")

      assert samples = Scrubber.encode_samples(secrets, basic_auth)

      assert Base.encode64("someuser:secretpassword") in samples
      assert Base.encode64("user@email.com:secretpassword") in samples

      assert MapSet.difference(
               MapSet.new([
                 "c2VjcmV0cGFzc3dvcmQ6c2VjcmV0cGFzc3dvcmQ=",
                 "c2VjcmV0cGFzc3dvcmQ6NTQzMg==",
                 "NTQzMjpzZWNyZXRwYXNzd29yZA==",
                 "YTpzZWNyZXRwYXNzd29yZA==",
                 "c2VjcmV0cGFzc3dvcmQ6YQ==",
                 "secretpassword",
                 "NTQzMjo1NDMy",
                 "YTo1NDMy",
                 "NTQzMjph",
                 "5432",
                 "YTph",
                 "a"
               ]),
               MapSet.new(samples)
             ) == MapSet.new()
    end
  end

  describe "scrub_values/1" do
    test "scrubs primitive values" do
      assert Scrubber.scrub_values("hello") == "string"
      assert Scrubber.scrub_values(42) == "number"
      assert Scrubber.scrub_values(3.14) == "number"
      assert Scrubber.scrub_values(true) == "boolean"
      assert Scrubber.scrub_values(false) == "boolean"
      assert Scrubber.scrub_values(nil) == "null"
    end

    test "preserves map keys while scrubbing values" do
      input = %{"name" => "John", "age" => 30}
      expected = %{"name" => "string", "age" => "number"}
      assert Scrubber.scrub_values(input) == expected
    end

    test "handles nested maps" do
      input = %{"user" => %{"name" => "John", "address" => %{"city" => "NYC"}}}

      expected = %{
        "user" => %{"name" => "string", "address" => %{"city" => "string"}}
      }

      assert Scrubber.scrub_values(input) == expected
    end

    test "scrubs arrays with sampling" do
      assert Scrubber.scrub_values([1, 2, 3]) == [
               "number",
               "number",
               "...1 more"
             ]

      assert Scrubber.scrub_values([1, 2]) == ["number", "number"]
      assert Scrubber.scrub_values([1]) == ["number"]
    end

    test "handles empty arrays" do
      assert Scrubber.scrub_values([]) == []
    end

    test "respects custom array_limit" do
      input = [1, 2, 3, 4, 5]

      assert Scrubber.scrub_values(input, 3) == [
               "number",
               "number",
               "number",
               "...2 more"
             ]

      assert Scrubber.scrub_values(input, 1) == ["number", "...4 more"]

      assert Scrubber.scrub_values(input, 5) == [
               "number",
               "number",
               "number",
               "number",
               "number"
             ]
    end

    test "handles complex nested structures with users and metadata" do
      input = %{
        "users" => [
          %{"name" => "John Doe", "age" => 34, "active" => true},
          %{"name" => "Jane Smith", "age" => 28, "active" => false},
          %{"name" => "Bob Wilson", "age" => 45, "active" => true}
        ],
        "metadata" => %{"total" => 3, "page" => 1}
      }

      expected = %{
        "users" => [
          %{"name" => "string", "age" => "number", "active" => "boolean"},
          %{"name" => "string", "age" => "number", "active" => "boolean"},
          "...1 more"
        ],
        "metadata" => %{"total" => "number", "page" => "number"}
      }

      assert Scrubber.scrub_values(input) == expected
    end
  end
end
