defmodule ValidatorsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Validators

  @valid_http_url "http://example.com"
  @valid_https_url "https://example.com"
  @valid_domain_url "https://sub.example.com"
  @valid_ip_url "https://192.168.1.1"
  @valid_ipv6_url "https://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]"
  @localhost_url "http://localhost"
  @invalid_scheme_url "ftp://example.com"
  @no_host_url "http://"
  @blank_host_url "http:///"
  @long_host_url "http://" <> String.duplicate("a", 256) <> ".com"
  @invalid_domain_url "https://-invalid-domain.com"
  @valid_ip_v6_url "http://[::1]"

  @invalid_url "invalid_url"

  def changeset(attrs \\ %{}) do
    {%{}, %{url: :string}}
    |> Ecto.Changeset.cast(attrs, [:url])
    |> Validators.validate_url(:url)
  end

  def email_changeset(attrs \\ %{}) do
    {%{}, %{email: :string}}
    |> Ecto.Changeset.cast(attrs, [:email])
    |> Validators.validate_email_format()
  end

  describe "validate_email_format/1" do
    test "accepts a standard email address" do
      assert email_changeset(%{email: "user@example.com"}).valid?
    end

    test "accepts plus-addressing" do
      assert email_changeset(%{email: "user+tag@example.com"}).valid?
    end

    test "accepts a single quote in the local part" do
      assert email_changeset(%{email: "o'reilly@example.com"}).valid?
    end

    test "accepts a minimal valid address" do
      assert email_changeset(%{email: "a@b.co"}).valid?
    end

    test "rejects email with no TLD (no dot in domain)" do
      changeset = email_changeset(%{email: "alice@local"})
      refute changeset.valid?
      assert ["must be a valid email address"] == errors_on(changeset).email
    end

    test "rejects email starting with a dot" do
      changeset = email_changeset(%{email: ".leading@example.com"})
      refute changeset.valid?
      assert ["must be a valid email address"] == errors_on(changeset).email
    end

    test "rejects email with consecutive dots" do
      changeset = email_changeset(%{email: "double..dot@example.com"})
      refute changeset.valid?
      assert ["must be a valid email address"] == errors_on(changeset).email
    end

    test "rejects blank email" do
      changeset = email_changeset(%{email: ""})
      refute changeset.valid?
      assert ["can't be blank"] == errors_on(changeset).email
    end

    test "rejects email longer than 160 characters" do
      changeset =
        email_changeset(%{email: String.duplicate("a", 156) <> "@b.co"})

      refute changeset.valid?
      assert ["should be at most 160 character(s)"] == errors_on(changeset).email
    end

    test "lowercases the email value" do
      changeset = email_changeset(%{email: "User@Example.COM"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :email) == "user@example.com"
    end
  end

  describe "validate_url/2" do
    test "validates http URLs" do
      assert changeset(%{url: @valid_http_url}).valid?
    end

    test "validates https URLs" do
      assert changeset(%{url: @valid_https_url}).valid?
    end

    test "validates URLs with subdomains" do
      assert changeset(%{url: @valid_domain_url}).valid?
    end

    test "validates URLs with IPv4 address" do
      assert changeset(%{url: @valid_ip_url}).valid?
    end

    test "validates URLs with IPv6 address" do
      assert changeset(%{url: @valid_ipv6_url}).valid?
    end

    test "validates localhost URLs" do
      assert changeset(%{url: @localhost_url}).valid?
    end

    test "invalidates URLs with an invalid scheme" do
      changeset = changeset(%{url: @invalid_scheme_url})
      refute changeset.valid?
      assert ["must be either a http or https URL"] == errors_on(changeset).url
    end

    test "invalidates URLs without a host" do
      changeset = changeset(%{url: @no_host_url})
      refute changeset.valid?
      assert ["host can't be blank"] == errors_on(changeset).url
    end

    test "invalidates URLs with a blank host" do
      changeset = changeset(%{url: @blank_host_url})
      refute changeset.valid?
      assert ["host can't be blank"] == errors_on(changeset).url
    end

    test "invalidates URLs with a host longer than 255 characters" do
      changeset = changeset(%{url: @long_host_url})
      refute changeset.valid?

      assert ["host must be less than 255 characters"] ==
               errors_on(changeset).url
    end

    test "invalidates URLs with invalid domain names" do
      changeset = changeset(%{url: @invalid_domain_url})
      refute changeset.valid?
      assert ["host has invalid characters"] == errors_on(changeset).url
    end

    test "validates URLs with valid IPv6 short form" do
      assert changeset(%{url: @valid_ip_v6_url}).valid?
    end

    test "invalidates URLs that are not valid at all" do
      changeset = changeset(%{url: @invalid_url})
      refute changeset.valid?
      assert ["must be either a http or https URL"] == errors_on(changeset).url
    end
  end
end
