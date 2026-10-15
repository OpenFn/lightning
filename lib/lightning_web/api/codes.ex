defmodule LightningWeb.API.Codes do
  @moduledoc """
  The API's codes: each response code with its status and fixed detail, and
  every code an error entry may carry. Both lists are the API's contract, so
  renaming or removing a code is a breaking change (error-format spec §6.4).
  """

  @response %{
    malformed: {400, "The body is not a JSON object."},
    invalid_parameter: {400, "A query parameter is not valid. See errors."},
    invalid_header: {400, "A request header is not valid. See errors."},
    unauthenticated: {401, "Authentication is required."},
    invalid_token: {401, "The token is not valid."},
    exceeds_limit: {402, "This would exceed a limit of your plan."},
    forbidden: {403, "You may not do this."},
    insufficient_scope: {403, "The token lacks the scope this needs."},
    trigger_disabled: {403, "This trigger is disabled."},
    not_found: {404, "Not found, or you don't have access to it."},
    not_acceptable:
      {406, "This resource cannot be returned in the requested format."},
    scheduled_for_deletion:
      {409, "This is scheduled for deletion. Cancel the deletion first."},
    id_taken: {409, "The id is already in use."},
    taken: {409, "A value that must be unique is already in use. See errors."},
    being_edited: {409, "This workflow is open in the editor."},
    ambiguous_name:
      {409, "More than one collection has this name. Add project_id."},
    export_conflict:
      {409, "Two items in this project export under the same key."},
    too_large: {413, "The body is too large."},
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

  @spec status(atom()) :: pos_integer()
  def status(code), do: @response |> Map.fetch!(code) |> elem(0)

  @spec detail(atom()) :: String.t()
  def detail(code), do: @response |> Map.fetch!(code) |> elem(1)

  @spec response_codes() :: [atom()]
  def response_codes, do: Map.keys(@response)

  @doc """
  The codes the walker maps from Ecto's own options, and those Lightning sets
  with `code:`.
  """
  @spec entry_codes() :: [atom()]
  def entry_codes,
    do: Enum.uniq(@ecto_entry_codes ++ Lightning.Validators.entry_codes())
end
