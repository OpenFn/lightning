defmodule Lightning.Extensions.RateLimiting do
  @moduledoc """
  Rate limiting for Lightning API endpoints.
  """
  alias Plug.Conn

  @type request_error :: :too_many_requests | :unknown
  @type message :: Lightning.Extensions.UsageLimiting.message()

  defmodule Context do
    @moduledoc """
    Which user is making the request for a certain project.
    """

    @type t :: %Context{
            project_id: Ecto.UUID.t(),
            user_id: Ecto.UUID.t() | nil
          }

    defstruct [:project_id, :user_id]
  end

  @callback limit_request(
              conn :: Conn.t(),
              context :: Context.t(),
              opts :: Keyword.t()
            ) ::
              :ok | {:error, request_error(), message()}
end
