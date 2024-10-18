defmodule Lightning.VersionControl.GithubClientTest do
  use Lightning.DataCase, async: true
  alias Lightning.VersionControl
  import Mox

  @cert """
  -----BEGIN RSA PRIVATE KEY-----
  MIICWwIBAAKBgQDdlatRjRjogo3WojgGHFHYLugdUWAY9iR3fy4arWNA1KoS8kVw33cJibXr8bvwUAUparCwlvdbH6dvEOfou0/gCFQsHUfQrSDv+MuSUMAe8jzKE4qW+jK+xQU9a03GUnKHkkle+Q0pX/g6jXZ7r1/xAK5Do2kQ+X5xK9cipRgEKwIDAQABAoGAD+onAtVye4ic7VR7V50DF9bOnwRwNXrARcDhq9LWNRrRGElESYYTQ6EbatXS3MCyjjX2eMhu/aF5YhXBwkppwxg+EOmXeh+MzL7Zh284OuPbkglAaGhV9bb6/5CpuGb1esyPbYW+Ty2PC0GSZfIXkXs76jXAu9TOBvD0ybc2YlkCQQDywg2R/7t3Q2OE2+yo382CLJdrlSLVROWKwb4tb2PjhY4XAwV8d1vy0RenxTB+K5Mu57uVSTHtrMK0GAtFr833AkEA6avx20OHo61Yela/4k5kQDtjEf1N0LfI+BcWZtxsS3jDM3i1Hp0KSu5rsCPb8acJo5RO26gGVrfAsDcIXKC+bQJAZZ2XIpsitLyPpuiMOvBbzPavd4gY6Z8KWrfYzJoI/Q9FuBo6rKwl4BFoToD7WIUS+hpkagwWiz+6zLoX1dbOZwJACmH5fSSjAkLRi54PKJ8TFUeOP15h9sQzydI8zJU+upvDEKZsZc/UhT/SySDOxQ4G/523Y0sz/OZtSWcol/UMgQJALesy++GdvoIDLfJX5GBQpuFgFenRiRDabxrE9MNUZ2aPFaFp+DyAe+b4nDwuJaW2LURbr8AEZga7oQj0uYxcYw==
  -----END RSA PRIVATE KEY-----
  """

  describe "GithubClient.build_installation_client/1" do
    setup :verify_on_exit!

    test "error is logged when 401 status code is received" do
      installation_id = "12345"
      resp_body = %{"something" => "wrong"}

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn %{
             url:
               "https://api.github.com/app/installations/" <>
                 ^installation_id <> "/access_tokens"
           },
           _opts ->
          {:ok, %Tesla.Env{status: 401, body: resp_body}}
        end
      )

      {result, log} =
        ExUnit.CaptureLog.with_log(fn ->
          VersionControl.GithubClient.build_installation_client(installation_id)
        end)

      assert {:error,
              %{
                code: :invalid_certificate,
                message: "GitHub Certificate is misconfigured"
              }} = result

      assert log =~ "Unexpected GitHub Response: #{inspect(resp_body)}"
    end

    test "error is logged when 404 status code is received" do
      installation_id = "12345"
      resp_body = %{"something" => "wrong"}

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn %{
             url:
               "https://api.github.com/app/installations/" <>
                 ^installation_id <> "/access_tokens"
           },
           _opts ->
          {:ok, %Tesla.Env{status: 404, body: resp_body}}
        end
      )

      {result, log} =
        ExUnit.CaptureLog.with_log(fn ->
          VersionControl.GithubClient.build_installation_client(installation_id)
        end)

      assert {:error,
              %{
                code: :installation_not_found,
                message: "GitHub Installation APP ID is misconfigured"
              }} = result

      assert log =~ "Unexpected GitHub Response: #{inspect(resp_body)}"
    end
  end

  describe "GithubToken" do
    test "builds a token" do
      Lightning.Stub.freeze_time(DateTime.utc_now())

      {:ok, token, claims} = VersionControl.GithubToken.build(@cert, "111111")

      assert %{
               "iss" => "111111",
               "exp" => exp,
               "iat" => iat
             } = claims

      assert iat ==
               Lightning.current_time()
               |> DateTime.add(-60, :second)
               |> DateTime.to_unix(),
             "iat should be 60s behind the current time"

      assert exp ==
               Lightning.current_time()
               |> DateTime.add(10, :minute)
               |> DateTime.to_unix(),
             "Expiry is 10 minutes from current time"

      assert {:ok, _claims} =
               VersionControl.GithubToken.verify_and_validate(
                 token,
                 Joken.Signer.create("RS256", %{"pem" => @cert}),
                 %{iss: "111111"}
               )
    end
  end
end
