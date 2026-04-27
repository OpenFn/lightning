defmodule Lightning.Workflows.Triggers.SyncWebhookResponseConfig do
  @moduledoc """
  Embedded schema for the default webhook response sent on run completion.

  When a trigger's `webhook_reply` is `:after_completion`, this config controls
  the HTTP response returned to the caller:

  - `success_code` — HTTP status code when the run succeeds. Defaults to 201.
  - `error_code` — HTTP status code for any non-success terminal state
    (failed, crashed, exception, killed, cancelled). Defaults to 201.
  - `body` — Custom response body (JSON). Falls back to the run's final state
    when nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:success_code, :error_code, :body]}

  @primary_key false
  embedded_schema do
    field :success_code, :integer
    field :error_code, :integer
    field :body, :map
  end

  def changeset(config, attrs) do
    cast(config, attrs, [:success_code, :error_code, :body])
  end
end
