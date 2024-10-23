defmodule Lightning.Credentials.Audit do
  @moduledoc """
  Model for storing changes to Credentials
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "credential",
    events: [
      "created",
      "updated",
      "added_to_project",
      "removed_from_project",
      "deleted"
    ]

  def update_changes(changes) when is_map(changes) do
    if Map.has_key?(changes, :body) do
      changes
      |> Map.update(:body, nil, fn val ->
        {:ok, val} = Lightning.Encrypted.Map.dump(val)
        Base.encode64(val)
      end)
    else
      changes
    end
  end

  def user_initiated_event(event, credential, changes \\ %{}) do
    %{id: id, user: user} = credential |> Lightning.Repo.preload(:user)

    event(event, id, user, changes)
  end
end
