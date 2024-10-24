defmodule Lightning.Credentials.OauthClientAudit do
  @moduledoc """
  Model for storing changes to Oauth clients
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "oauth_client",
    events: [
      "created",
      "updated",
      "added_to_project",
      "removed_from_project",
      "deleted"
    ]

  def update_changes(changes) when is_map(changes) do
    changes
    |> encode_key(:client_id)
    |> encode_key(:client_secret)
  end

  defp encode_key(changes, key) do
    if Map.has_key?(changes, key) do
      Map.update!(changes, key, &Base.encode64/1)
    else
      changes
    end
  end

  def user_initiated_event(event, client, changes \\ %{}) do
    %{id: id, user: user} = client |> Lightning.Repo.preload(:user)

    event(event, id, user, changes)
  end
end
