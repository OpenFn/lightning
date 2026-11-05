defmodule Lightning.Elixir119RegressionsTest do
  use ExUnit.Case, async: true

  alias Lightning.Validators

  # `Validators.validate_url/2` accepts a URL through `URI.new/1`, and the
  # request is later built from `URI.parse/1` (PinnedAdapter.port/2 for OAuth
  # token endpoints, Philter for channel destinations), which falls back to the
  # scheme's default port when it reads no port.
  describe "a URL validate_url accepts" do
    for port <- [65_535, 65_536, 99_999] do
      test "keeps its port #{port} when parsed for the request" do
        url = "https://idp.example.org:#{unquote(port)}/token"

        changeset =
          {%{}, %{url: :string}}
          |> Ecto.Changeset.cast(%{url: url}, [:url])
          |> Validators.validate_url(:url)

        assert not changeset.valid? or URI.parse(url).port == unquote(port)
      end
    end
  end
end
