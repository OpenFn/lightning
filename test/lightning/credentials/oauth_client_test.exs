defmodule Lightning.Credentials.OauthClientTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.OauthClient

  describe "changeset/2" do
    @valid_attrs %{
      name: "Example Client",
      client_id: "client123",
      client_secret: "secret456",
      authorization_endpoint: "https://example.com/auth",
      token_endpoint: "https://example.com/token",
      userinfo_endpoint: "https://example.com/user",
      scopes_doc_url: "https://example.com/scopes"
    }

    @invalid_attrs %{
      name: nil,
      client_id: nil,
      client_secret: nil,
      authorization_endpoint: "badurl",
      token_endpoint: "badurl",
      userinfo_endpoint: "badurl",
      scopes_doc_url: "badurl"
    }

    test "creates a valid changeset with required attributes" do
      changeset = OauthClient.changeset(%OauthClient{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires essential fields" do
      changeset = OauthClient.changeset(%OauthClient{}, %{})

      assert [
               name: {"can't be blank", [validation: :required]},
               client_id: {"can't be blank", [validation: :required]},
               client_secret: {"can't be blank", [validation: :required]},
               authorization_endpoint:
                 {"can't be blank", [validation: :required]},
               token_endpoint: {"can't be blank", [validation: :required]}
             ] === changeset.errors
    end

    test "validates URLs are well-formed" do
      url_fields = [
        :authorization_endpoint,
        :token_endpoint,
        :userinfo_endpoint,
        :scopes_doc_url
      ]

      changeset = OauthClient.changeset(%OauthClient{}, @invalid_attrs)

      Enum.each(url_fields, fn field ->
        assert {"must be either a http or https URL", []} ==
                 changeset.errors[field]
      end)
    end

    test "URLS that are not required can be null" do
      attrs = %{
        userinfo_endpoint: nil,
        scopes_doc_url: nil
      }

      changeset =
        OauthClient.changeset(%OauthClient{}, attrs)

      keys_with_errors = Keyword.keys(changeset.errors)

      Map.keys(attrs)
      |> Enum.each(fn key -> assert key not in keys_with_errors end)
    end

    test "Any other type of URL is invalid" do
      attrs = %{
        userinfo_endpoint: 123,
        scopes_doc_url: false
      }

      changeset =
        OauthClient.changeset(%OauthClient{}, attrs)

      Map.keys(attrs)
      |> Enum.each(fn key ->
        assert {"is invalid", [type: :string, validation: :cast]} ==
                 changeset.errors[key]
      end)
    end

    test "creates changeset with optional attributes" do
      optional_attrs = Map.put_new(@valid_attrs, :global, true)
      changeset = OauthClient.changeset(%OauthClient{}, optional_attrs)

      assert changeset.valid?
      assert changeset.changes.global == true
    end

    test "handles association casts for projects" do
      assoc_attrs =
        Map.merge(@valid_attrs, %{
          project_oauth_clients: [%{project_id: Ecto.UUID.generate()}]
        })

      changeset = OauthClient.changeset(%OauthClient{}, assoc_attrs)

      assert changeset.valid?
      assert length(changeset.changes.project_oauth_clients) == 1
    end
  end
end
