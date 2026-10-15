defmodule LightningWeb.API.Problem do
  @moduledoc """
  An RFC 9457 problem document (error-format spec §2), and the one function
  that sends one.
  """
  alias LightningWeb.API.Codes
  alias LightningWeb.API.Errors

  @enforce_keys [:status, :code]
  defstruct [:status, :code, errors: [], extensions: %{}, headers: []]

  @type t :: %__MODULE__{
          status: pos_integer(),
          code: atom(),
          errors: [Errors.entry()],
          extensions: map(),
          headers: [{String.t(), String.t()}]
        }

  @doc """
  Builds the problem for a response code from `LightningWeb.API.Codes`.

  Options:

    * `:errors` - the entries, from `LightningWeb.API.Errors`.
    * `:status` - overrides the code's status. Only `/i/*` needs it, to keep
      429 for a plan limit (spec §12).
    * `:extensions` - members the spec names for this answer, such as
      `existing` or `work_order_id`.
    * `:headers` - response headers that belong to the answer, such as
      `retry-after`.
  """
  @spec new(atom(), keyword()) :: t()
  def new(code, opts \\ []) do
    %__MODULE__{
      code: code,
      status: Keyword.get_lazy(opts, :status, fn -> Codes.status(code) end),
      errors: Keyword.get(opts, :errors, []),
      extensions: Keyword.get(opts, :extensions, %{}),
      headers: Keyword.get(opts, :headers, [])
    }
  end

  @doc """
  Sends `problem` as the response.

  The body is the same whatever the request's `Accept`. The content type is
  `application/problem+json` only when `Accept` names it, and
  `application/json` otherwise (spec §5).
  """
  @spec respond(Plug.Conn.t(), t()) :: Plug.Conn.t()
  def respond(conn, %__MODULE__{} = problem) do
    conn
    |> Plug.Conn.put_resp_content_type(content_type(conn))
    |> Plug.Conn.merge_resp_headers(problem.headers)
    |> Plug.Conn.send_resp(
      problem.status,
      Jason.encode_to_iodata!(body(problem))
    )
  end

  defp body(problem) do
    %{
      type: "about:blank",
      status: problem.status,
      title: Plug.Conn.Status.reason_phrase(problem.status),
      code: problem.code,
      detail: Codes.detail(problem.code)
    }
    |> then(fn body ->
      if problem.errors == [],
        do: body,
        else: Map.put(body, :errors, problem.errors)
    end)
    |> Map.merge(problem.extensions)
  end

  defp content_type(conn) do
    asks_for_problem? =
      conn
      |> Plug.Conn.get_req_header("accept")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.any?(fn range ->
        range |> String.split(";") |> hd() |> String.trim() |> String.downcase() ==
          "application/problem+json"
      end)

    if asks_for_problem?,
      do: "application/problem+json",
      else: "application/json"
  end
end
