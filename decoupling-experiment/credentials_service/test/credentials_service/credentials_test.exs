defmodule CredentialsService.CredentialsTest do
  use CredentialsService.DataCase, async: false

  alias CredentialsService.Credentials
  alias CredentialsService.Credentials.Credential
  alias CredentialsService.Projects.ProjectCredential

  defp user_id, do: Ecto.UUID.generate()

  describe "create_credential/1" do
    test "persists a credential with a default 'main' environment body" do
      uid = user_id()

      assert {:ok, %Credential{} = cred} =
               Credentials.create_credential(%{
                 "name" => "My API Key",
                 "schema" => "http",
                 "user_id" => uid,
                 "body" => %{"username" => "u", "password" => "supersecret"}
               })

      assert cred.user_id == uid
      assert [body] = cred.credential_bodies
      assert body.name == "main"
    end

    test "stores the body ENCRYPTED at rest (ciphertext, not plaintext)" do
      uid = user_id()

      {:ok, cred} =
        Credentials.create_credential(%{
          "name" => "Encrypted",
          "user_id" => uid,
          "body" => %{"password" => "supersecret-marker"}
        })

      %{rows: [[raw]]} =
        Repo.query!(
          "SELECT body FROM credential_bodies WHERE credential_id = $1",
          [Ecto.UUID.dump!(cred.id)]
        )

      assert is_binary(raw)
      refute raw =~ "supersecret-marker"
    end

    test "supports multiple environments via 'bodies'" do
      {:ok, cred} =
        Credentials.create_credential(%{
          "name" => "Multi Env",
          "user_id" => user_id(),
          "bodies" => %{
            "main" => %{"token" => "a"},
            "staging" => %{"token" => "b"}
          }
        })

      names = cred.credential_bodies |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["main", "staging"]
    end

    test "rejects an invalid name with a changeset error" do
      assert {:error, changeset} =
               Credentials.create_credential(%{
                 "name" => "bad/name!",
                 "user_id" => user_id(),
                 "body" => %{"k" => "v"}
               })

      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "rejects a body with too many sensitive values" do
      big = for i <- 1..51, into: %{}, do: {"k#{i}", "v#{i}"}

      assert {:error, changeset} =
               Credentials.create_credential(%{
                 "name" => "Too Many",
                 "user_id" => user_id(),
                 "body" => big
               })

      # error surfaces on the nested credential_bodies changeset
      assert changeset.errors != [] or
               match?(
                 [%{body: [_ | _]} | _],
                 Enum.map(changeset.changes.credential_bodies, &errors_on/1)
               )
    end
  end

  describe "listing & fetching" do
    test "list_credentials/1 returns only the user's credentials" do
      uid = user_id()
      other = user_id()
      {:ok, _} = Credentials.create_credential(base_attrs("Mine", uid))
      {:ok, _} = Credentials.create_credential(base_attrs("Theirs", other))

      assert [%Credential{name: "Mine"}] = Credentials.list_credentials(uid)
    end

    test "list_credentials_for_project/1 follows the join" do
      uid = user_id()
      project_id = Ecto.UUID.generate()

      {:ok, _} =
        Credentials.create_credential(
          base_attrs("Shared", uid)
          |> Map.put("project_credentials", [%{"project_id" => project_id}])
        )

      assert [%Credential{name: "Shared"}] =
               Credentials.list_credentials_for_project(project_id)
    end

    test "get_credential/1 returns nil for unknown id and non-UUID input" do
      assert Credentials.get_credential(Ecto.UUID.generate()) == nil
      assert Credentials.get_credential("not-a-uuid") == nil
    end
  end

  describe "delete_credential/1" do
    test "deletes the credential and its project_credentials join rows" do
      uid = user_id()
      project_id = Ecto.UUID.generate()

      {:ok, cred} =
        Credentials.create_credential(
          base_attrs("ToDelete", uid)
          |> Map.put("project_credentials", [%{"project_id" => project_id}])
        )

      assert Repo.aggregate(
               from(pc in ProjectCredential, where: pc.credential_id == ^cred.id),
               :count
             ) == 1

      assert {:ok, _} = Credentials.delete_credential(cred)

      assert Credentials.get_credential(cred.id) == nil

      assert Repo.aggregate(
               from(pc in ProjectCredential, where: pc.credential_id == ^cred.id),
               :count
             ) == 0
    end
  end

  describe "pure OAuth/sensitive logic (no DB)" do
    test "oauth_token_expired?/2 honours the 5-minute buffer" do
      now = 1_000_000
      # expires in 200s -> within the 300s buffer -> expired
      assert Credentials.oauth_token_expired?(%{"expires_at" => now + 200}, now)
      # expires in 600s -> not expired
      refute Credentials.oauth_token_expired?(%{"expires_at" => now + 600}, now)
      refute Credentials.oauth_token_expired?(%{"no" => "expiry"}, now)
    end

    test "sensitive_values/1 collects nested string leaves" do
      body = %{"a" => "x", "nested" => %{"b" => "y"}, "list" => ["z"], "n" => 5}
      assert Enum.sort(Credentials.sensitive_values(body)) == ["x", "y", "z"]
    end
  end

  defp base_attrs(name, uid),
    do: %{"name" => name, "user_id" => uid, "body" => %{"k" => "v"}}

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
