defmodule Lightning.GithubHelpers do
  @moduledoc false

  @public_key """
  -----BEGIN PUBLIC KEY-----
  MIIBITANBgkqhkiG9w0BAQEFAAOCAQ4AMIIBCQKCAQB1ZtDWukVcNcnMLXUsi8Mw
  6WK5pri2sXuNZpT8lMf2fXcEmsJdvEhP3DASDykLyusJp9fV17BzM8JmzC9zNMIc
  OdLhwsl8rKoVrwYjFXXRvPn+5QzpwT/JprymE54lbFJ/lMefkfkJcaSl5khyHNpl
  rGH5g7+zGiMfs+kXItjhW41xEsy552kff3Wq/33R2sdizIDDJjEC/6J942jLpMJe
  HgYaZXZRKsc9b6CSjZS/nVh0OA/bE4deNrSDesyytcMmN3/+l9XYbQqJOgVs/sWl
  TNPEVQabXsPxzIwVGcH+iDRhV31nqe6YoQ/gvNTRnESnC1KRrTB7eCwZP0kHLshX
  AgMBAAE=
  -----END PUBLIC KEY-----
  """

  def set_valid_github_oauth_token!(user) do
    active_token = %{
      "access_token" => "access-token",
      "refresh_token" => "refresh-token",
      "expires_at" => DateTime.utc_now() |> DateTime.add(500),
      "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(500)
    }

    user
    |> Ecto.Changeset.change(%{github_oauth_token: active_token})
    |> Lightning.Repo.update!()
  end

  def expect_get_user_installations(
        resp_status \\ 200,
        resp_body \\ %{
          "installations" => [
            %{
              "id" => 1234,
              "account" => %{
                "type" => "User",
                "login" => "username"
              }
            }
          ]
        }
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{url: "https://api.github.com/user/installations"}, _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_get_installation_repos(
        resp_status \\ 200,
        resp_body \\ %{
          "repositories" => [
            %{
              "full_name" => "someaccount/somerepo",
              "default_branch" => "main"
            }
          ]
        }
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{url: "https://api.github.com/installation/repositories"}, _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_get_repo_branches(
        repo,
        resp_status \\ 200,
        resp_body \\ [%{"name" => "somebranch"}]
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{url: "https://api.github.com/repos/" <> ^repo <> "/branches"},
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_get_repo(
        repo,
        resp_status \\ 200,
        resp_body \\ %{
          "full_name" => "someaccount/somerepo",
          "default_branch" => "main"
        }
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url: "https://api.github.com/repos/" <> ^repo
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_get_repo_content(
        repo,
        content_path,
        resp_status \\ 200,
        resp_body \\ %{"sha" => "somesha"}
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           method: :get,
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/contents/" <> ^content_path
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_delete_repo_content(
        repo,
        content_path,
        resp_status \\ 200,
        resp_body \\ %{"sha" => "somesha"}
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           method: :delete,
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/contents/" <> ^content_path
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_update_ref(
        repo,
        branch,
        resp_status \\ 200,
        resp_body \\ %{"ref" => "refs/heads/master"}
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/git/refs/heads/" <> ^branch
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_create_blob(
        repo,
        resp_status \\ 201,
        resp_body \\ %{"sha" => "3a0f8"}
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url: "https://api.github.com/repos/" <> ^repo <> "/git/blobs"
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_create_tree(
        repo,
        resp_status \\ 201,
        resp_body \\ %{"sha" => "7abcd"}
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url: "https://api.github.com/repos/" <> ^repo <> "/git/trees"
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_create_commit(
        repo,
        resp_status \\ 201,
        resp_body \\ %{"sha" => "7abcd"}
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url: "https://api.github.com/repos/" <> ^repo <> "/git/commits"
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_get_commit(
        repo,
        branch,
        resp_status \\ 200,
        resp_body \\ %{
          "sha" => "6dc",
          "commit" => %{"tree" => %{"sha" => "7ec"}}
        }
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/commits/heads/" <> ^branch
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_get_public_key(
        repo,
        resp_status \\ 200,
        resp_body \\ %{
          "key" => Base.encode64(@public_key),
          "key_id" => "012345678912345678"
        }
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/actions/secrets/public-key"
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_create_repo_secret(
        repo,
        secret_name,
        resp_status \\ 201,
        resp_body \\ ""
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/actions/secrets/" <> ^secret_name
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_delete_repo_secret(
        repo,
        secret_name,
        resp_status \\ 204,
        resp_body \\ ""
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           method: :delete,
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/actions/secrets/" <> ^secret_name
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_create_installation_token(
        installation_id,
        resp_status \\ 201,
        resp_body \\ %{"token" => "some-token"}
      ) do
    installation_id = to_string(installation_id)

    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url:
             "https://api.github.com/app/installations/" <>
               ^installation_id <> "/access_tokens"
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end

  def expect_create_workflow_dispatch(
        repo,
        workflow_path,
        resp_status \\ 204,
        resp_body \\ ""
      ) do
    Mox.expect(
      Lightning.Tesla.Mock,
      :call,
      fn %{
           url:
             "https://api.github.com/repos/" <>
               ^repo <> "/actions/workflows/" <> ^workflow_path <> "/dispatches"
         },
         _opts ->
        {:ok, %Tesla.Env{status: resp_status, body: resp_body}}
      end
    )
  end
end
