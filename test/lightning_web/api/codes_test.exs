defmodule LightningWeb.API.CodesTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.Codes

  @lib Path.expand("../../../lib", __DIR__)

  defp codes_set_in(dir) do
    "#{@lib}/#{dir}/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      Regex.scan(~r/\bcode: :(\w+)/, File.read!(file), capture: :all_but_first)
    end)
    |> MapSet.new(fn [code] -> String.to_atom(code) end)
  end

  test "every code lib/lightning sets with code: is in a code list" do
    # `not_ready` is set but never sent as an entry (spec §6.2).
    known = MapSet.new([:not_ready | Codes.entry_codes()])

    assert MapSet.difference(codes_set_in("lightning"), known) == MapSet.new()
  end

  test "every code Lightning is listed as setting is set somewhere in lib" do
    # An entry code may be set in lightning_web, where an API controller
    # validates the request itself.
    set = MapSet.union(codes_set_in("lightning"), codes_set_in("lightning_web"))

    assert MapSet.difference(MapSet.new(Codes.lightning_entry_codes()), set) ==
             MapSet.new()
  end

  test "every response code answers with its status and detail" do
    expected = %{
      bad_request: {400, "The request could not be read."},
      invalid_request: {400, "The credentials could not be read."},
      malformed: {400, "The body is not a JSON object."},
      invalid_parameter:
        {400, "A path or query parameter is not valid. See errors."},
      invalid_header: {400, "A request header is not valid. See errors."},
      unauthenticated: {401, "Authentication is required."},
      invalid_token: {401, "The token is not valid."},
      exceeds_limit: {402, "This would exceed a limit of your plan."},
      forbidden: {403, "You may not do this (or it might not exist)."},
      insufficient_scope: {403, "The token lacks the token grant this needs."},
      trigger_disabled: {403, "This trigger is disabled."},
      not_found: {404, "Not found."},
      not_acceptable:
        {406, "This resource cannot be returned in the requested format."},
      request_timeout: {408, "The request body did not arrive in time."},
      scheduled_for_deletion:
        {409, "This is scheduled for deletion. Cancel the deletion first."},
      id_taken: {409, "The id is already in use."},
      being_edited: {409, "This workflow is open in the editor."},
      concurrent_edit:
        {409,
         "Another request changed or deleted this record. Fetch it again and retry."},
      in_use: {409, "This has been used by runs and cannot be deleted."},
      ambiguous_name:
        {409, "More than one collection has this name. Add project_id."},
      export_conflict:
        {409, "Two items in this project export under the same key."},
      content_too_large: {413, "The body is too large."},
      uri_too_long: {414, "The query string is too long."},
      unsupported_media_type: {415, "The body must be JSON."},
      invalid: {422, "The request is not valid. See errors."},
      too_many_runs: {429, "Too many runs. Try again later."},
      too_many_requests: {429, "Too many requests. Try again later."},
      internal: {500, "Something went wrong."},
      not_implemented: {501, "This is not available on this instance."},
      bad_gateway: {502, "The channel could not reach its destination."},
      service_unavailable: {503, "Try again shortly."},
      not_ready: {503, "This is not ready yet. Try again shortly."},
      timeout: {504, "The workflow did not finish in time."}
    }

    actual =
      Map.new(
        Codes.response_codes(),
        &{&1, {Codes.status(&1), Codes.detail(&1)}}
      )

    assert actual == expected
  end

  describe "for_exception/2" do
    test "every exception with a 4xx status has a code for that status" do
      for exception <- client_exceptions() do
        status = Plug.Exception.status(exception)
        code = Codes.for_exception(:error, exception)

        assert code != :internal,
               "#{inspect(exception)} answers #{status} with no code"

        assert Codes.status(code) == status,
               "#{inspect(exception)} answers #{status} as #{code}"
      end
    end

    test "a raise a client did not cause is internal" do
      for {kind, reason} <- [
            error: %Ecto.StaleEntryError{},
            error: %Ecto.Query.CastError{},
            error: %RuntimeError{},
            exit: :timeout,
            throw: :oops
          ] do
        assert Codes.for_exception(kind, reason) == :internal
      end
    end
  end

  describe "for_limiter/1" do
    test "answers each reason Lightning names with its code" do
      assert Codes.for_limiter(:too_many_runs) == :too_many_runs
      assert Codes.for_limiter(:too_many_requests) == :too_many_requests
      assert Codes.for_limiter(:unknown) == :too_many_requests
    end

    test "answers any other reason with exceeds_limit, never a raise" do
      for reason <- [:too_many_workflows, :disabled, :runs_cap_exceeded] do
        assert Codes.for_limiter(reason) == :exceeds_limit
      end
    end
  end

  # Every exception these apps give a 4xx status, through a `plug_status`
  # field or a `Plug.Exception` implementation, so an upgrade that adds one
  # fails here until it has a code.
  defp client_exceptions do
    {:consolidated, implemented} = Plug.Exception.__protocol__(:impls)

    with_field =
      [:lightning, :plug, :phoenix, :phoenix_live_view]
      |> Enum.flat_map(&Application.spec(&1, :modules))
      |> Enum.filter(&plug_status_field?/1)

    defaults =
      (implemented ++ with_field)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in [Any, Ecto.Query.CastError, Ecto.StaleEntryError]))
      |> Enum.map(&struct/1)

    others = [
      %Plug.Conn.InvalidQueryError{plug_status: 414},
      %Postgrex.Error{postgres: %{code: :character_not_in_repertoire}}
    ]

    Enum.filter(defaults ++ others, &(Plug.Exception.status(&1) in 400..499))
  end

  defp plug_status_field?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :exception, 1) and
      Map.get(module.__struct__(), :plug_status) != nil
  end
end
