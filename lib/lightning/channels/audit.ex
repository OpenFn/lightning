defmodule Lightning.Channels.Audit do
  @moduledoc """
  Audit trail for channel CRUD operations.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "channel",
    events: [
      "created",
      "updated",
      "deleted"
    ]
end
