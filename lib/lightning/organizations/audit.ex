defmodule Lightning.Organizations.Audit do
  @moduledoc """
  Audit events for organizations: creating and renaming one, and adding,
  re-roling and removing its members.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "organization",
    events: [
      "created",
      "updated",
      "member_added",
      "member_role_changed",
      "member_removed"
    ]

  @doc false
  def member_fields(%{user: %{email: email}}, role),
    do: %{"email" => email, "role" => to_string(role)}
end
