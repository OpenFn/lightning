defmodule Lightning.Extensions.RateLimiting do
  @moduledoc """
  Rate limiting for Lightning API endpoints.
  """
  alias Plug.Conn

  @type request_error :: :too_many_requests | :unknown
  @type message :: Lightning.Extensions.Message.t()

  defmodule Context do
    @type t :: %Context{project_id: Ecto.UUID.t()}

    defstruct [:project_id]
  end

  @callback limit_request(
              conn :: Conn.t(),
              context :: Context.t(),
              opts :: Keyword.t()
            ) ::
              :ok | {:error, request_error(), message()}
end
