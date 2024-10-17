defmodule ValidatorsTest do
  use Lightning.DataCase, async: true

  import Ecto.Changeset

  defmodule TestSchema do
    use Ecto.Schema

    embedded_schema do
      field :url, :string
    end
  end

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
    %TestSchema{}
    |> cast(attrs, [:url])
    |> Validators.validate_url(:url)
  end

  describe "validate_url/2" do
    test "validates http URLs" do
      changeset = changeset(%{url: @valid_http_url})
      assert changeset.valid?
    end

    test "validates https URLs" do
      changeset = changeset(%{url: @valid_https_url})
      assert changeset.valid?
    end

    test "validates URLs with subdomains" do
      changeset = changeset(%{url: @valid_domain_url})
      assert changeset.valid?
    end

    test "validates URLs with IPv4 address" do
      changeset = changeset(%{url: @valid_ip_url})
      assert changeset.valid?
    end

    test "validates URLs with IPv6 address" do
      changeset = changeset(%{url: @valid_ipv6_url})
      assert changeset.valid?
    end

    test "validates localhost URLs" do
      changeset = changeset(%{url: @localhost_url})
      assert changeset.valid?
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
      changeset = changeset(%{url: @valid_ip_v6_url})
      assert changeset.valid?
    end

    test "invalidates URLs that are not valid at all" do
      changeset = changeset(%{url: @invalid_url})
      refute changeset.valid?
      assert ["must be either a http or https URL"] == errors_on(changeset).url
    end
  end
end
