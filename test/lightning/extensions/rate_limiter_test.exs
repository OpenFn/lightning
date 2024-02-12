defmodule Lightning.Extensions.RateLimiterTest do
  use LightningWeb.ConnCase

  alias Lightning.Extensions.RateLimiting.Context
  alias Lightning.Extensions.RateLimiter

  test "rate limit is not exceeded", %{conn: conn} do
    assert RateLimiter.limit_request(
             conn,
             %Context{
               project_id: Ecto.UUID.generate(),
               user_id: Ecto.UUID.generate()
             },
             []
           ) == :ok
  end
end
