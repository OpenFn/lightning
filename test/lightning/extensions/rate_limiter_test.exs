defmodule Lightning.Extensions.RateLimiterTest do
  use LightningWeb.ConnCase

  alias Lightning.Extensions.RateLimiting.Context
  alias Lightning.Extensions.RateLimiter

  test "rate limit is not exceeded", %{conn: conn} do
    Enum.each(1..100, fn _i ->
      assert RateLimiter.limit_request(
               conn,
               %Context{
                 project_id: Ecto.UUID.generate(),
                 user_id: Ecto.UUID.generate()
               },
               []
             ) == :ok
    end)
  end
end
