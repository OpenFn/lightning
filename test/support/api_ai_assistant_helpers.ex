defmodule LightningWeb.ApiAiAssistantHelpers do
  @moduledoc """
  Builders for the answers `GET /api/ai_assistant/sessions` gives, for API tests.
  """

  @doc """
  The `updated_at` the route writes for `session`, a record as inserted.
  """
  def updated_at(session),
    do: NaiveDateTime.to_iso8601(session.updated_at) <> "Z"

  @doc """
  The `pagination` member of an answer.
  """
  def pagination(total_count, opts \\ []) do
    %{
      "total_count" => total_count,
      "has_next_page" => Keyword.get(opts, :next, false),
      "has_prev_page" => Keyword.get(opts, :prev, false)
    }
  end
end
