defmodule Lightning.ScrubberTest do
  use ExUnit.Case, async: true

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
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

    test "replaces only value secrets in a map with ***" do
      secrets = ["password", "immasecret", "username", "quux"]
      scrubber = start_supervised!({Lightning.Scrubber, samples: secrets})

      scrubbed =
        scrubber
        |> Scrubber.scrub([
          %{
            "password" => "immasecret",
            "username" => "quux",
            "fieldA" => "valueA"
          }
        ])

      assert scrubbed == [
               %{"password" => "***", "username" => "***", "fieldA" => "valueA"}
             ]
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
               "secretpassword",
               "NTQzMjo1NDMy",
               "YTo1NDMy",
               "NTQzMjph",
               "5432",
               "YTph",
               "a"
             ]
    end

    test "adds basic auth base64 composed with usernames" do
      secrets = ["a", "secretpassword", 5432, false]

      basic_auth =
        Credentials.basic_auth_for(%Credential{
          body: %{
            "username" => "someuser",
            "email" => "user@email.com",
            "password" => "secretpassword"
          }
        })

      assert samples =
               Scrubber.encode_samples(
                 secrets,
                 basic_auth
               )

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

      assert Base.encode64("someuser:secretpassword") in samples
      assert Base.encode64("user@email.com:secretpassword") in samples
    end
  end
end
