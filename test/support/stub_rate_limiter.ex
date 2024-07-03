defmodule Lightning.Extensions.StubRateLimiter do
  @behaviour Lightning.Extensions.RateLimiting

  alias Lightning.Extensions.Message

  def limit_request(_conn, _context, _opts) do
    {:error, :too_many_requests,
     %Message{text: "Too many runs in the last minute"}}
  end
end
