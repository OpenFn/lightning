defmodule LightningWeb.API.Problem do
  @moduledoc """
  An RFC 9457 problem document (error-format spec §2), and the one function
  that sends one.
  """
  alias LightningWeb.API.Codes
  alias LightningWeb.API.Errors
  alias Plug.Conn.Utils

  @enforce_keys [:status, :code]
  defstruct [:status, :code, errors: [], extensions: %{}, headers: []]

  @type t :: %__MODULE__{
          status: pos_integer(),
          code: Codes.code(),
          errors: [Errors.entry()],
          extensions: map(),
          headers: [{String.t(), String.t()}]
        }

  @doc """
  Builds the problem for a response code from `LightningWeb.API.Codes`.

  Options:

    * `:errors` - the entries, from `LightningWeb.API.Errors`.
    * `:extensions` - members the spec names for this answer, such as
      `existing` or `work_order_id`.
    * `:headers` - response headers that belong to the answer.
    * `:retry_after` - seconds, sent as `retry-after`; `nil` sends none.
    * `:status` - one of `LightningWeb.API.Codes.statuses/1` for `code`
      other than its own, where the spec keeps a route's status (§12).
  """
  @spec new(Codes.code(), keyword()) :: t()
  def new(code, opts \\ []) do
    status = Keyword.get(opts, :status, Codes.status(code))

    unless status in Codes.statuses(code) do
      raise ArgumentError, "#{inspect(code)} is never sent at #{status}"
    end

    %__MODULE__{
      code: code,
      status: status,
      errors: Keyword.get(opts, :errors, []),
      extensions: Keyword.get(opts, :extensions, %{}),
      headers:
        Keyword.get(opts, :headers, []) ++
          retry_after_header(Keyword.get(opts, :retry_after))
    }
  end

  defp retry_after_header(nil), do: []

  defp retry_after_header(seconds),
    do: [{"retry-after", Integer.to_string(seconds)}]

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

  @doc """
  Sends `problem` as the response, as `respond/2` does, and halts the plug
  pipeline.
  """
  @spec halt(Plug.Conn.t(), t()) :: Plug.Conn.t()
  def halt(conn, %__MODULE__{} = problem) do
    conn
    |> respond(problem)
    |> Plug.Conn.halt()
  end

  @doc """
  The problem document `respond/2` sends.
  """
  @spec body(t()) :: map()
  def body(problem) do
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

  @doc """
  The content type a problem sent on `conn` takes: `application/problem+json`
  when the request's `Accept` names it, in any position and whatever its `q`,
  and `application/json` otherwise (spec §5).
  """
  @spec content_type(Plug.Conn.t()) :: String.t()
  def content_type(conn) do
    asks_for_problem? =
      conn
      |> Plug.Conn.get_req_header("accept")
      |> Enum.flat_map(&Utils.list/1)
      |> Enum.any?(
        &match?(
          {:ok, "application", "problem+json", _params},
          Utils.media_type(&1)
        )
      )

    if asks_for_problem?,
      do: "application/problem+json",
      else: "application/json"
  end
end
