defmodule LightningWeb.API.ApiDocGrantsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount.AccessToken

  @api_md Path.expand("../../../API.md", __DIR__)
  @external_resource @api_md

  @rows ~r/^\| `([A-Z]+)` +\| `(\/api[^`]*)` +\|[^|]*\| (.+?) +\|$/m
        |> Regex.scan(File.read!(@api_md), capture: :all_but_first)
        |> Enum.reject(fn [_verb, _path, cell] ->
          cell in ["None", "Session only"]
        end)

  setup %{conn: conn} do
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  for [verb, path, cell] <- @rows do
    @verb verb
    @path path

    case Regex.run(~r/^`([a-z]+:[a-z]+)`$/, cell, capture: :all_but_first) do
      [grant] ->
        @grant grant

        test "#{verb} #{path} needs #{grant}, as API.md says", %{conn: conn} do
          {conn, _account} =
            with_service_account(conn, AccessToken.scopes() -- [@grant])

          conn = request(conn, @verb, @path)

          assert {conn.status, code(conn)} == {403, "insufficient_scope"},
                 "#{@verb} #{@path} answered #{answer(conn)} to a token " <>
                   "holding every grant but #{@grant}, which API.md says it needs"

          assert_refused_for_scope(conn, @grant)
        end

      nil when cell == "Not open to the service account" ->
        test "#{verb} #{path} refuses the service account, as API.md says", %{
          conn: conn
        } do
          {conn, _account} = with_service_account(conn, AccessToken.scopes())
          conn = request(conn, @verb, @path)

          assert {conn.status, code(conn)} == {403, "forbidden"},
                 "#{@verb} #{@path} answered #{answer(conn)} to a token " <>
                   "holding every grant, though API.md says it is not open to " <>
                   "the service account"

          assert_problem(conn, 403, :forbidden, [])
        end

      nil ->
        @cell cell

        test "#{verb} #{path}'s grant cell names one grant or a fixed phrase" do
          flunk(
            "#{@verb} #{@path}'s grant cell holds #{inspect(@cell)}. Give " <>
              "it one grant in backticks, \"Not open to the service " <>
              "account\", \"None\" or \"Session only\"."
          )
        end
    end
  end

  defp request(conn, verb, path) do
    path = Regex.replace(~r/:[a-z_]+/, path, fn _ -> Ecto.UUID.generate() end)
    dispatch(conn, @endpoint, verb, path)
  end

  defp answer(conn), do: "#{conn.status} with code #{inspect(code(conn))}"

  defp code(conn) do
    case Jason.decode(conn.resp_body) do
      {:ok, %{"code" => code}} -> code
      _other -> nil
    end
  end
end
