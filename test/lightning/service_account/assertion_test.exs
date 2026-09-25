defmodule Lightning.ServiceAccount.AssertionTest do
  use Lightning.DataCase, async: true

  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount.Assertion

  @audience "https://lightning.example/api/oauth/token"

  setup do
    {account, private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)
    %{account: account, private_key: private_key}
  end

  defp verify(private_key, claims) do
    private_key |> sign_assertion(claims) |> Assertion.verify(@audience)
  end

  describe "verify/2" do
    test "accepts an assertion from the registered service account", %{
      account: account,
      private_key: private_key
    } do
      assert {:ok, ^account} =
               verify(private_key, assertion_claims(account, @audience))
    end

    test "accepts an aud holding only the token endpoint", %{
      account: account,
      private_key: private_key
    } do
      claims = assertion_claims(account, @audience, %{"aud" => [@audience]})
      assert {:ok, ^account} = verify(private_key, claims)
    end

    test "refuses a jti it has already seen", %{
      account: account,
      private_key: private_key
    } do
      claims = assertion_claims(account, @audience)

      assert {:ok, _} = verify(private_key, claims)
      assert {:error, :replayed} = verify(private_key, claims)
    end

    test "refuses an aud other than the token endpoint", %{
      account: account,
      private_key: private_key
    } do
      for aud <- [
            "https://elsewhere.example/api/oauth/token",
            [@audience, "https://elsewhere.example"],
            nil
          ] do
        claims = assertion_claims(account, @audience, %{"aud" => aud})
        assert {:error, :wrong_audience} = verify(private_key, claims)
      end
    end

    test "refuses an expired assertion", %{
      account: account,
      private_key: private_key
    } do
      now = System.system_time(:second)

      claims =
        assertion_claims(account, @audience, %{
          "iat" => now - 61,
          "exp" => now - 1
        })

      assert {:error, :expired} = verify(private_key, claims)
    end

    test "refuses an assertion that lives longer than 60 seconds", %{
      account: account,
      private_key: private_key
    } do
      now = System.system_time(:second)

      claims =
        assertion_claims(account, @audience, %{"iat" => now, "exp" => now + 61})

      assert {:error, :lives_too_long} = verify(private_key, claims)
    end

    test "refuses an assertion issued in the future", %{
      account: account,
      private_key: private_key
    } do
      now = System.system_time(:second)

      claims =
        assertion_claims(account, @audience, %{
          "iat" => now + 600,
          "exp" => now + 660
        })

      assert {:error, :issued_in_future} = verify(private_key, claims)
    end

    test "refuses an assertion missing exp, iat or jti", %{
      account: account,
      private_key: private_key
    } do
      for claim <- ["exp", "iat", "jti"] do
        claims = account |> assertion_claims(@audience) |> Map.delete(claim)
        assert {:error, _} = verify(private_key, claims)
      end
    end

    test "refuses a jti that is too long or holds a NUL", %{
      account: account,
      private_key: private_key
    } do
      for jti <- [String.duplicate("a", 256), "a\u0000b"] do
        claims = assertion_claims(account, @audience, %{"jti" => jti})
        assert {:error, :missing_claims} = verify(private_key, claims)
      end
    end

    test "refuses an assertion whose sub is not its iss", %{
      account: account,
      private_key: private_key
    } do
      claims = assertion_claims(account, @audience, %{"sub" => "someone-else"})
      assert {:error, :wrong_subject} = verify(private_key, claims)
    end

    test "refuses a key it does not know", %{account: account} do
      {stranger, stranger_key} = service_account_with_key()
      claims = assertion_claims(stranger, @audience)

      assert {:error, :unknown_service_account} = verify(stranger_key, claims)

      Mox.stub(Lightning.MockConfig, :service_account, fn -> nil end)
      claims = assertion_claims(account, @audience)
      assert {:error, :unknown_service_account} = verify(stranger_key, claims)
    end

    test "refuses a bad signature", %{account: account} do
      {_stranger, stranger_key} = service_account_with_key()
      claims = assertion_claims(account, @audience)

      assert {:error, :bad_signature} = verify(stranger_key, claims)
    end

    test "refuses alg none and HS256 signed with the public key", %{
      account: account
    } do
      claims = assertion_claims(account, @audience)
      {_, public_pem} = JOSE.JWK.to_pem(account.public_key)
      hmac_key = JOSE.JWK.from_oct(public_pem)

      assert {:error, :bad_signature} =
               claims |> unsigned_assertion() |> Assertion.verify(@audience)

      assert {:error, :bad_signature} =
               hmac_key
               |> sign_assertion(claims, %{"alg" => "HS256"})
               |> Assertion.verify(@audience)
    end

    test "refuses something that is not a JWT" do
      assert {:error, :malformed} = Assertion.verify("not.a.jwt", @audience)
      assert {:error, :malformed} = Assertion.verify("", @audience)
    end

    test "records a jti only once the assertion checks out", %{
      account: account,
      private_key: private_key
    } do
      claims = assertion_claims(account, @audience, %{"aud" => "wrong"})
      assert {:error, :wrong_audience} = verify(private_key, claims)

      claims = Map.put(claims, "aud", @audience)
      assert {:ok, _} = verify(private_key, claims)
    end
  end

  describe "perform/1" do
    test "deletes the jtis of assertions expired over five minutes ago", %{
      account: account,
      private_key: private_key
    } do
      [old, recent, live] =
        for _ <- 1..3 do
          claims = assertion_claims(account, @audience)
          assert {:ok, _} = verify(private_key, claims)
          claims["jti"]
        end

      now = DateTime.utc_now()

      for {jti, seconds} <- [{old, -301}, {recent, -1}] do
        Repo.update_all(
          from(a in "service_account_assertions", where: a.jti == ^jti),
          set: [expires_at: DateTime.add(now, seconds)]
        )
      end

      assert :ok = perform_job(Assertion, %{})

      assert Repo.all(from(a in "service_account_assertions", select: a.jti))
             |> Enum.sort() == Enum.sort([recent, live])
    end
  end
end
