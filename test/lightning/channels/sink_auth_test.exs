defmodule Lightning.Channels.SinkAuthTest do
  use ExUnit.Case, async: true

  alias Lightning.Channels.SinkAuth

  describe "supported_schemas/0" do
    test "returns expected schemas" do
      assert SinkAuth.supported_schemas() == ["http", "dhis2", "oauth"]
    end
  end

  describe "build_auth_header/2 with http schema" do
    test "Bearer token from access_token" do
      assert {:ok, "Bearer tok-123"} =
               SinkAuth.build_auth_header("http", %{"access_token" => "tok-123"})
    end

    test "Basic auth from username and password" do
      expected = "Basic #{Base.encode64("user:pass")}"

      assert {:ok, ^expected} =
               SinkAuth.build_auth_header("http", %{
                 "username" => "user",
                 "password" => "pass"
               })
    end

    test "access_token takes priority over username/password" do
      assert {:ok, "Bearer tok-priority"} =
               SinkAuth.build_auth_header("http", %{
                 "access_token" => "tok-priority",
                 "username" => "user",
                 "password" => "pass"
               })
    end

    test "error when no auth fields present" do
      assert {:error, :no_auth_fields} =
               SinkAuth.build_auth_header("http", %{
                 "baseUrl" => "https://example.com"
               })
    end

    test "error when body is empty" do
      assert {:error, :no_auth_fields} =
               SinkAuth.build_auth_header("http", %{})
    end
  end

  describe "build_auth_header/2 with dhis2 schema" do
    test "ApiToken from pat" do
      assert {:ok, "ApiToken d2pat_abc"} =
               SinkAuth.build_auth_header("dhis2", %{"pat" => "d2pat_abc"})
    end

    test "Basic auth from username and password" do
      expected = "Basic #{Base.encode64("admin:secret")}"

      assert {:ok, ^expected} =
               SinkAuth.build_auth_header("dhis2", %{
                 "username" => "admin",
                 "password" => "secret"
               })
    end

    test "pat takes priority over username/password" do
      assert {:ok, "ApiToken my-pat"} =
               SinkAuth.build_auth_header("dhis2", %{
                 "pat" => "my-pat",
                 "username" => "admin",
                 "password" => "secret"
               })
    end

    test "error when no auth fields present" do
      assert {:error, :no_auth_fields} =
               SinkAuth.build_auth_header("dhis2", %{
                 "hostUrl" => "https://play.dhis2.org"
               })
    end
  end

  describe "build_auth_header/2 with oauth schema" do
    test "Bearer token from access_token" do
      assert {:ok, "Bearer oauth-tok"} =
               SinkAuth.build_auth_header("oauth", %{
                 "access_token" => "oauth-tok"
               })
    end

    test "error when no access_token" do
      assert {:error, :no_auth_fields} =
               SinkAuth.build_auth_header("oauth", %{
                 "refresh_token" => "refresh-only"
               })
    end

    test "error when body is empty" do
      assert {:error, :no_auth_fields} =
               SinkAuth.build_auth_header("oauth", %{})
    end
  end

  describe "build_auth_header/2 with unsupported schemas" do
    test "raw schema returns unsupported error" do
      assert {:error, {:unsupported_schema, "raw"}} =
               SinkAuth.build_auth_header("raw", %{"key" => "val"})
    end

    test "postgresql schema returns unsupported error" do
      assert {:error, {:unsupported_schema, "postgresql"}} =
               SinkAuth.build_auth_header("postgresql", %{"host" => "localhost"})
    end
  end
end
