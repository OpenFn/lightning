defmodule LightningWeb.API.ProblemHelpers do
  @moduledoc """
  Assertions on problem documents, for API tests (error-format spec §14).
  """
  import ExUnit.Assertions

  alias LightningWeb.API.Codes
  alias LightningWeb.API.Problem

  @sentinel "sentinel-5e17f4c2"

  @doc """
  Asserts `conn` answered with the problem for `code` at `status`, and returns
  the decoded body.

  It checks the content type against the request's `Accept`, the members
  `LightningWeb.API.Codes` fixes, and that every code, the response's and each
  entry's, is in one of the two code lists. `entries` is `:any`, or the exact
  list of entries in any order, as decoded JSON:
  `[%{"pointer" => "#/name", "code" => "required", "detail" => "can't be blank"}]`.
  """
  def assert_problem(conn, status, code, entries \\ :any) do
    assert conn.status == status

    assert [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
    [media_type | _params] = String.split(content_type, ";")
    assert media_type == Problem.content_type(conn)

    body = Jason.decode!(conn.resp_body)

    assert code in Codes.response_codes()

    assert status == Codes.status(code)

    assert Map.take(body, ["type", "status", "title", "code", "detail"]) == %{
             "type" => "about:blank",
             "status" => status,
             "title" => Plug.Conn.Status.reason_phrase(status),
             "code" => Atom.to_string(code),
             "detail" => Codes.detail(code)
           }

    entry_codes = Enum.map(Codes.entry_codes(), &Atom.to_string/1)

    for entry <- Map.get(body, "errors", []) do
      assert entry["code"] in entry_codes,
             "#{inspect(entry["code"])} is in neither code list (spec §6.4)"
    end

    if entries != :any do
      assert Enum.sort(Map.get(body, "errors", [])) == Enum.sort(entries)
    end

    body
  end

  @doc """
  Asserts each of `conns` was refused 403 `insufficient_scope` naming `grant`,
  so the answers can't tell an existing target from a missing one (spec §4
  row 2, §9.2).
  """
  def assert_refused_for_scope(conns, grant) do
    for conn <- conns do
      assert_problem(conn, 403, :insufficient_scope)

      assert Plug.Conn.get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer error="insufficient_scope", scope="#{grant}")
             ]
    end
  end

  @doc """
  Replaces every value in `params`, at any depth, with a marker that must
  never come back in an answer. Keys are kept, since a pointer may name them.
  """
  def plant_sentinel(params) when is_map(params),
    do: Map.new(params, fn {key, value} -> {key, plant_sentinel(value)} end)

  def plant_sentinel(params) when is_list(params),
    do: Enum.map(params, &plant_sentinel/1)

  def plant_sentinel(_value), do: @sentinel

  @doc """
  Asserts that no value `plant_sentinel/1` planted came back in the answer
  (spec §3 rule 3).
  """
  def refute_sentinel(conn) do
    refute conn.resp_body =~ @sentinel,
           "the answer quotes a value from the request: #{conn.resp_body}"

    conn
  end
end
