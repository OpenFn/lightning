defmodule Lightning.RateLimitersTest do
  use ExUnit.Case, async: true

  alias Lightning.RateLimiters

  describe "Mail" do
    test "returns a hit result" do
      id = Ecto.UUID.generate()
      assert RateLimiters.Mail.hit(id, 1, 1) == {:allow, 1}
      assert RateLimiters.Mail.hit(id, 1, 1) == {:deny, 1000}
    end
  end
end
