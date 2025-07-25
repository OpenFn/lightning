defmodule Lightning.Policies.Collections do
  @moduledoc """
  The Bodyguard Policy module for Collections.

  Access to collections is controlled by the project the collection belongs to.

  The `access_collection` action is allowed if the user has access to the
  project, or if a run belongs to the project (via it's workflow).
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Collections.Collection
  alias Lightning.Policies.Permissions
  alias Lightning.Run

  @type actions :: :access_collection
  @spec authorize(actions(), Lightning.Accounts.User.t(), Collection.t()) ::
          :ok | {:error, :unauthorized}
  def authorize(:access_collection, %User{} = user, %Collection{} = collection) do
    Permissions.can(:project_users, :access_project, user, collection)
  end

  def authorize(:access_collection, %Run{} = run, %Collection{} = collection) do
    Lightning.Runs.get_project_id_for_run(run) == collection.project_id
  end
end
