defmodule LightningWeb.Plugs.Redirect do
  @moduledoc """
  A plug for redirecting requests to a specified URL.

  This plug takes an option `:to` which specifies the target URL for the redirection.
  """

  use Phoenix.Controller
  import Plug.Conn

  @doc """
  Initializes the plug options.

  ## Parameters

    - opts: A keyword list of options.

  ## Returns

  The provided options are returned as they are.

  ## Examples

      iex> LightningWeb.Plugs.Redirect.init(to: "/new_path")
      [to: "/new_path"]
  """
  def init(opts) do
    opts
  end

  @doc """
  Redirects the connection to the specified URL.

  ## Parameters

    - conn: The connection struct.
    - opts: A keyword list of options. Must include `:to` key specifying the target URL.

  ## Examples

      iex> conn = %Plug.Conn{}
      iex> opts = [to: "/new_path"]
      iex> LightningWeb.Plugs.Redirect.call(conn, opts)
      %Plug.Conn{...}

  ## Raises

  `KeyError` if the `:to` key is not present in options.
  """
  def call(conn, opts) do
    to = Keyword.fetch!(opts, :to)

    conn
    |> redirect(to: to)
    |> halt()
  end
end
