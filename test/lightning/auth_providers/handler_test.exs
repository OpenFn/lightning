defmodule Lightning.AuthProviders.HandlerTest do
  use ExUnit.Case, async: true

  import Lightning.BypassHelpers

  alias Lightning.AuthProviders.Handler
  alias Lightning.AuthProviders.WellKnown

  defp build_handler(name, wellknown) do
    {:ok, handler} =
      Handler.new(name,
        wellknown: wellknown,
        client_id: "id",
        client_secret: "secret",
        redirect_uri: "http://localhost/callback"
      )

    handler
  end

  describe "get_userinfo/2 with a GitHub-style emails endpoint" do
    setup do
      bypass = Bypass.open()

      wellknown = %WellKnown{
        authorization_endpoint: "#{endpoint_url(bypass)}/authorization_endpoint",
        token_endpoint: "#{endpoint_url(bypass)}/token_endpoint",
        userinfo_endpoint: "#{endpoint_url(bypass)}/userinfo_endpoint",
        user_emails_endpoint: "#{endpoint_url(bypass)}/user_emails_endpoint"
      }

      {:ok,
       handler: build_handler("github", wellknown),
       bypass: bypass,
       token: OAuth2.AccessToken.new("access-token")}
    end

    test "resolves the primary verified email when userinfo has none", ctx do
      expect_userinfo(ctx.bypass, ctx.handler.wellknown, %{"sub" => "1"})

      expect_user_emails(ctx.bypass, ctx.handler.wellknown, [
        %{
          "email" => "second@example.com",
          "primary" => false,
          "verified" => true
        },
        %{
          "email" => "primary@example.com",
          "primary" => true,
          "verified" => true
        },
        %{"email" => "nope@example.com", "primary" => false, "verified" => false}
      ])

      {:ok, userinfo} = Handler.get_userinfo(ctx.handler, ctx.token)

      assert userinfo["email"] == "primary@example.com"
      assert userinfo["email_verified"] == true
    end

    test "falls back to any verified email when none is primary", ctx do
      expect_userinfo(ctx.bypass, ctx.handler.wellknown, %{"sub" => "1"})

      expect_user_emails(ctx.bypass, ctx.handler.wellknown, [
        %{
          "email" => "unverified@example.com",
          "primary" => true,
          "verified" => false
        },
        %{
          "email" => "verified@example.com",
          "primary" => false,
          "verified" => true
        }
      ])

      {:ok, userinfo} = Handler.get_userinfo(ctx.handler, ctx.token)

      assert userinfo["email"] == "verified@example.com"
      assert userinfo["email_verified"] == true
    end

    test "treats a present public profile email as verified without a second call",
         ctx do
      expect_userinfo(ctx.bypass, ctx.handler.wellknown, %{
        "sub" => "1",
        "email" => "public@example.com"
      })

      # No expect_user_emails/3 stub: Bypass fails the test if /user/emails is hit.
      {:ok, userinfo} = Handler.get_userinfo(ctx.handler, ctx.token)

      assert userinfo["email"] == "public@example.com"
      assert userinfo["email_verified"] == true
    end

    test "leaves userinfo unresolved when no verified email is available", ctx do
      expect_userinfo(ctx.bypass, ctx.handler.wellknown, %{"sub" => "1"})

      expect_user_emails(ctx.bypass, ctx.handler.wellknown, [
        %{
          "email" => "unverified@example.com",
          "primary" => true,
          "verified" => false
        }
      ])

      {:ok, userinfo} = Handler.get_userinfo(ctx.handler, ctx.token)

      refute Map.has_key?(userinfo, "email")
      refute userinfo["email_verified"]
    end
  end

  describe "get_userinfo/2 with a standard OIDC provider" do
    test "returns userinfo unchanged when there is no emails endpoint" do
      bypass = Bypass.open()

      wellknown = %WellKnown{
        authorization_endpoint: "#{endpoint_url(bypass)}/authorization_endpoint",
        token_endpoint: "#{endpoint_url(bypass)}/token_endpoint",
        userinfo_endpoint: "#{endpoint_url(bypass)}/userinfo_endpoint"
      }

      handler = build_handler("google", wellknown)

      expect_userinfo(bypass, wellknown, %{
        "sub" => "1",
        "email" => "g@example.com",
        "email_verified" => true
      })

      {:ok, userinfo} =
        Handler.get_userinfo(handler, OAuth2.AccessToken.new("token"))

      assert userinfo["email"] == "g@example.com"
      assert userinfo["email_verified"] == true
    end

    test "returns an error tuple instead of raising when userinfo fails" do
      bypass = Bypass.open()

      wellknown = %WellKnown{
        authorization_endpoint: "#{endpoint_url(bypass)}/authorization_endpoint",
        token_endpoint: "#{endpoint_url(bypass)}/token_endpoint",
        userinfo_endpoint: "#{endpoint_url(bypass)}/userinfo_endpoint"
      }

      handler = build_handler("google", wellknown)

      expect_userinfo(bypass, wellknown, {500, ~s({"error": "boom"})})

      assert {:error, _reason} =
               Handler.get_userinfo(handler, OAuth2.AccessToken.new("token"))
    end
  end
end
