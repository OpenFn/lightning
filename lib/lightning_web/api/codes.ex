defmodule LightningWeb.API.Codes do
  @moduledoc """
  The API's codes: each response code with its status and fixed detail, and
  every code an error entry may carry. Both lists are the API's contract.
  Adding a code is compatible. Renaming or removing one, or moving it to another
  status, is a breaking change.
  """

  @response %{
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

  @typedoc "A response code, one of the keys of the response list."
  @type code ::
          unquote(Enum.reduce(Map.keys(@response), &{:|, [], [&1, &2]}))

  # `/i/*` keeps 429 for every limiter refusal (spec §12).
  @other_statuses %{exceeds_limit: [429]}

  @by_status %{
    400 => :bad_request,
    403 => :forbidden,
    404 => :not_found,
    406 => :not_acceptable,
    408 => :request_timeout,
    413 => :content_too_large,
    414 => :uri_too_long,
    415 => :unsupported_media_type
  }

  @ecto_entry_codes [
    :duplicate,
    :format,
    :invalid,
    :must_accept,
    :mismatch,
    :not_allowed,
    :not_found,
    :out_of_range,
    :required,
    :reserved,
    :taken,
    :too_long,
    :too_short,
    :type,
    :wrong_length
  ]

  # `not_ready` is set with `code:` too, but it is not listed here. It never
  # reaches the client as an entry, only as the 503 response code (spec §6.2).
  @lightning_entry_codes [
    :already_scheduled,
    :credential_not_allowed,
    :cycle,
    :dataclip_wiped,
    :deleting,
    :discovery_failed,
    :exceeds_limit,
    :exclusive,
    :invalid,
    :mismatch,
    :missing_trigger_edge,
    :no_access,
    :not_found,
    :not_supported,
    :one_body,
    :one_enabled,
    :one_enabled_edge,
    :one_owner,
    :scope_not_granted,
    :single_target,
    :storage_failed,
    :too_many_secrets,
    :tree_branch_conflict,
    :trigger_removed,
    :unchanged,
    :unknown_key
  ]

  @spec status(code()) :: pos_integer()
  def status(code), do: @response |> Map.fetch!(code) |> elem(0)

  @doc "Every status `code` may answer with, its own first."
  @spec statuses(code()) :: [pos_integer()]
  def statuses(code), do: [status(code) | Map.get(@other_statuses, code, [])]

  @spec detail(code()) :: String.t()
  def detail(code), do: @response |> Map.fetch!(code) |> elem(1)

  # phoenix_ecto gives these a 4xx status, but Lightning raises them where it
  # should have returned an error, so `for_exception/2` answers `:internal`.
  @raised_by_lightning [Ecto.Query.CastError, Ecto.StaleEntryError]

  @doc """
  The code a raise is answered with. Every exception a client can cause has a
  4xx status (`Plug.Exception.status/1`) and is answered by it. Anything else
  is `:internal`: a 500 means Lightning raised where it should not have.
  """
  @spec for_exception(:error | :exit | :throw, term()) :: code()
  def for_exception(:error, %Plug.Parsers.ParseError{}), do: :malformed

  def for_exception(:error, %exception{})
      when exception in @raised_by_lightning,
      do: :internal

  def for_exception(:error, exception),
    do: Map.get(@by_status, Plug.Exception.status(exception), :internal)

  def for_exception(_kind, _reason), do: :internal

  @doc """
  The code a usage or rate limiter's refusal is answered with (spec §4, §12).
  The limiter's text is copy for the app's pages, so it never reaches the
  answer.
  """
  @spec for_limiter(atom()) :: code()
  def for_limiter(:too_many_runs), do: :too_many_runs

  def for_limiter(reason) when reason in [:too_many_requests, :unknown],
    do: :too_many_requests

  # The usage limiter is an extension that picks its own reasons, so any other
  # is the plan's limit.
  def for_limiter(_reason), do: :exceeds_limit

  @spec response_codes() :: [code()]
  def response_codes, do: Map.keys(@response)

  @doc """
  The codes the walker maps from Ecto's own options, and those Lightning sets
  with `code:`.
  """
  @spec entry_codes() :: [atom()]
  def entry_codes, do: Enum.uniq(@ecto_entry_codes ++ @lightning_entry_codes)

  @doc false
  @spec lightning_entry_codes() :: [atom()]
  def lightning_entry_codes, do: @lightning_entry_codes
end
