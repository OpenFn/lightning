defmodule Lightning.Workflows.Triggers.SyncWebhookResponseConfig do
  @moduledoc """
  Embedded schema for the default webhook response sent on run completion.

  When a trigger's `webhook_reply` is `:after_completion`, this config controls
  the HTTP response returned to the caller:

  - `code` — HTTP status code. Falls back to 200 (success) or 400 (any other
    terminal state) when nil.
  - `body` — Custom response body. Falls back to the run's final state when nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :code, :integer
    field :body, :map
  end

  def changeset(config, attrs) do
    cast(config, attrs, [:code, :body])
  end
end
