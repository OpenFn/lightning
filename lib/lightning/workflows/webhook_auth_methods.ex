defmodule Lightning.Workflows.WebhookAuthMethodAudit do
  @moduledoc """
  Model for storing changes to WebhookAuthMethod
  """
  use Lightning.Auditing.Model,
    repo: Lightning.Repo,
    item: "webhook_auth_method",
    events: [
      "created",
      "updated",
      "added_to_trigger",
      "removed_from_trigger",
      "deleted"
    ]
end
