defmodule Lightning.Credentials.Audit do
  @moduledoc """
  Model for storing changes to Credentials
  """
  use Lightning.Auditing.Model,
    repo: Lightning.Repo,
    item: "credential",
    events: [
      "created",
      "updated",
      "added_to_project",
      "removed_from_project",
      "deleted"
    ]
end
