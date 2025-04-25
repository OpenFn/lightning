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

  describe "Webhook" do
    setup do
      Mox.stub_with(LightningMock, Lightning.API)

      :ok
    end

    test "returns a hit result" do
      id = Ecto.UUID.generate()
      assert RateLimiters.Webhook.hit(id, 1, 1) == {:allow, 1}
      assert RateLimiters.Webhook.hit(id, 1, 1) == {:deny, 1000}
    end

    test "returns a hit result for a project id" do
      # 10 requests per second, then denied for 1 second
      id = Ecto.UUID.generate()

      for i <- 1..10 do
        assert RateLimiters.hit({:webhook, id}) == {:allow, i}
        Process.sleep(5)
      end

      assert RateLimiters.hit({:webhook, id}) == {:deny, 1000}

      Process.sleep(1005)

      # Leaked by 2, then add 1 for the next hit.
      assert RateLimiters.hit({:webhook, id}) == {:allow, 9}
    end
  end
end
