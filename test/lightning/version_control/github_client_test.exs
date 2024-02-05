defmodule Lightning.VersionControl.GithubClientTest do
  use Lightning.DataCase, async: false
  alias Lightning.VersionControl
  import Lightning.Factories
  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]

  @cert """
  -----BEGIN RSA PRIVATE KEY-----
  MIICWwIBAAKBgQDdlatRjRjogo3WojgGHFHYLugdUWAY9iR3fy4arWNA1KoS8kVw33cJibXr8bvwUAUparCwlvdbH6dvEOfou0/gCFQsHUfQrSDv+MuSUMAe8jzKE4qW+jK+xQU9a03GUnKHkkle+Q0pX/g6jXZ7r1/xAK5Do2kQ+X5xK9cipRgEKwIDAQABAoGAD+onAtVye4ic7VR7V50DF9bOnwRwNXrARcDhq9LWNRrRGElESYYTQ6EbatXS3MCyjjX2eMhu/aF5YhXBwkppwxg+EOmXeh+MzL7Zh284OuPbkglAaGhV9bb6/5CpuGb1esyPbYW+Ty2PC0GSZfIXkXs76jXAu9TOBvD0ybc2YlkCQQDywg2R/7t3Q2OE2+yo382CLJdrlSLVROWKwb4tb2PjhY4XAwV8d1vy0RenxTB+K5Mu57uVSTHtrMK0GAtFr833AkEA6avx20OHo61Yela/4k5kQDtjEf1N0LfI+BcWZtxsS3jDM3i1Hp0KSu5rsCPb8acJo5RO26gGVrfAsDcIXKC+bQJAZZ2XIpsitLyPpuiMOvBbzPavd4gY6Z8KWrfYzJoI/Q9FuBo6rKwl4BFoToD7WIUS+hpkagwWiz+6zLoX1dbOZwJACmH5fSSjAkLRi54PKJ8TFUeOP15h9sQzydI8zJU+upvDEKZsZc/UhT/SySDOxQ4G/523Y0sz/OZtSWcol/UMgQJALesy++GdvoIDLfJX5GBQpuFgFenRiRDabxrE9MNUZ2aPFaFp+DyAe+b4nDwuJaW2LURbr8AEZga7oQj0uYxcYw==
  -----END RSA PRIVATE KEY-----
  """

  describe "Non success Github Client" do
    setup do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      Tesla.Mock.mock(fn env ->
        case env.url do
          "https://api.github.com/app/installations/some-id/access_tokens" ->
            %Tesla.Env{status: 401, body: %{}}

          "https://api.github.com/app/installations/fail-id/access_tokens" ->
            %Tesla.Env{status: 404, body: %{}}

          "https://api.github.com/installation/repositories" ->
            %Tesla.Env{status: 404, body: %{}}

          "https://api.github.com/repos/some/repo/branches" ->
            %Tesla.Env{status: 401, body: %{}}
        end
      end)
    end

    @tag :capture_log
    test "client can handle invalid application message from github" do
      p_repo = insert(:project_repo_connection)

      assert {:error,
              %{
                code: :invalid_certificate,
                message: "Github Certificate is misconfigured"
              }} =
               VersionControl.fetch_installation_repos(p_repo.project_id)
    end

    @tag :capture_log
    test "client can handle invalid PEM message from github" do
      p_repo =
        insert(:project_repo_connection, github_installation_id: "fail-id")

      assert {:error,
              %{
                code: :installation_not_found,
                message: "Github Installation APP ID is misconfigured"
              }} =
               VersionControl.initiate_sync(p_repo.project_id, "some-user-name")
    end

    @tag :capture_log
    test "fetch repo branches can handle fail" do
      p_repo = insert(:project_repo_connection)

      assert {:error,
              %{
                code: :invalid_certificate,
                message: "Github Certificate is misconfigured"
              }} =
               VersionControl.fetch_repo_branches(p_repo.project_id, p_repo.repo)
    end

    @tag :capture_log
    test "client can fetch installation repos" do
      p_repo = insert(:project_repo_connection)

      assert {:error,
              %{
                code: :invalid_certificate,
                message: "Github Certificate is misconfigured"
              }} =
               VersionControl.fetch_installation_repos(p_repo.project_id)
    end
  end

  describe "Github Client" do
    setup do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      Tesla.Mock.mock(fn env ->
        case env.url do
          "https://api.github.com/app/installations/some-id/access_tokens" ->
            %Tesla.Env{status: 201, body: %{"token" => "some-token"}}

          "https://api.github.com/installation/repositories" ->
            %Tesla.Env{
              status: 200,
              body: %{"repositories" => [%{"full_name" => "org/repo"}]}
            }

          "https://api.github.com/repos/some/repo/branches" ->
            %Tesla.Env{status: 200, body: [%{"name" => "master"}]}

          "https://api.github.com/repos/some/repo/dispatches" ->
            %Tesla.Env{status: 204, body: %{}}
        end
      end)
    end

    test "client can fetch installation repos" do
      p_repo = insert(:project_repo_connection)

      assert {:ok, ["org/repo"]} =
               VersionControl.fetch_installation_repos(p_repo.project_id)
    end

    test "client can fetch repo branches" do
      p_repo = insert(:project_repo_connection)

      assert {:ok, ["master"]} =
               VersionControl.fetch_repo_branches(p_repo.project_id, p_repo.repo)
    end

    test "client can fire repository dispatch event" do
      p_repo = insert(:project_repo_connection)

      assert {:ok, :fired} =
               VersionControl.initiate_sync(p_repo.project_id, "some-user-name")
    end
  end

  describe "GithubToken" do
    test "builds a token" do
      {:ok, token, claims} = VersionControl.GithubToken.build(@cert, "111111")

      assert %{
               "iss" => "111111",
               "exp" => exp,
               "iat" => iat,
               "nbf" => nbf,
               "aud" => "Joken",
               "jti" => _
             } = claims

      current_time = Joken.current_time()

      assert iat in Range.new(current_time - 61, current_time - 59),
             "IAT is not 1 minute before the current time"

      # 10 minutes
      expected_expiry = current_time + 60 * 10

      assert exp in Range.new(expected_expiry - 1, expected_expiry + 1),
             "Expiry is not within 1 second of expected expiry"

      assert nbf >= Joken.current_time()

      assert Joken.verify_and_validate(
               VersionControl.GithubToken.token_config()
               |> Map.update("iss", nil, fn claim ->
                 %{claim | validate: fn val, _, _ -> val == "111111" end}
               end),
               token,
               Joken.Signer.create("RS256", %{"pem" => @cert})
             )
    end
  end
end
