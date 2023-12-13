defmodule Lightning.Workflows.WebhookAuthMethodAudit do
  @moduledoc """
  Model for storing changes to WebhookAuthMethod
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "webhook_auth_method",
    events: [
      "created",
      "updated",
      "added_to_trigger",
      "removed_from_trigger",
      "deleted"
    ]

  @impl true
  def update_changes(changes) when is_map(changes) do
    Enum.into(changes, %{}, fn
      {key, val} when key in [:username, :password, :api_key] ->
        {:ok, encrypted_val} = Lightning.Encrypted.Binary.dump(val)
        {key, Base.encode64(encrypted_val)}

      other ->
        other
    end)
  end
end
