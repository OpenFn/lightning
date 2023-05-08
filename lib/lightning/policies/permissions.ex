defmodule Lightning.Policies.Permissions do
  @moduledoc """
  This module defines a unique interface managing authorizations in Lightning.

  Authorization is a central part of Lightning. Users have different access levels
  and can do different things depending on their access levels.

  Lightning has 2 types of access levels:
  1. Instance wide access levels - those are the superuser level and the normal users level.
  - Superusers are the administrator of the Lightning instance, they can manage projects, manage users,
  define authentications, access the audit trail, etc.
  - Normal users are the other users of the Lightning. They are managed by superusers and have full access on their own data.
  They can manage their accounts and their credentials and can be part of projects.
  2. Project wide access levels - those are the access levels project members can have. They are viewer, editor, admin, and owner.
  - viewer is the level 0, it's the lowest access level. It allows actions like accessing the resources of the project in read only
    mode and editing their own membership configurations (i.e digest alerts, failure alerts)
  - editor is the level 1. It allows actions like accessing the resources in read / write mode.
    Project members with editor access level can do what project members with viewer role can do and more.
    They can create / edit / delete / run / rerun jobs and create workflows
  - admin is the level 2. It allows administration access to project members.
    Admins of a project can do what editors can do and more. They can edit the project name and description
    and also add new project members to the project (collaborators).
  - owner is the level 3 and the highest level of access in a project. Owners are the creators of project.
    They can do what all other levels can do and more. Owners can delete projects.

  These authorizations policies are all implemented under the `lib/lightning/policies` folder. In that folder you can find 3 files:
  - The `users.ex` file has all the policies for the instances wide access levels
  - The `project_users.ex` file has all the policies for the project wide access levels
  - The `permissions.ex` file defines the `Lightning.Policies.Permissions.can/4` interface. Which is a wrapper around the `Bodyguard.permit/4` function.
  We use that interface to be able to harmonize the use of policies accross the entire app.

  All the policies are tested in the `test/lightning/policies` folder. And the test are written in a way that allows the reader to quickly who can do what in the app.

  We have two variants of the `Lightning.Policies.Permissions.can/4` interface:
  - `Lightning.Policies.Permissions.can(policy, action, actor, resource)` returns `:ok` if the actor can perform the action on the resource and `{:error, :unauthorized}` otherwise.
  - `Lightning.Policies.Permissions.can?(policy, action, actor, resource)` returns `true` if the actor can perform the action on the resource and `false` otherwise.

  Here is an example of how we the `Lightning.Policies.Permissions.can/4` interface to check if the a user can edit a job or not
  ```elixir
  can_edit_job = Lightning.Policies.ProjectUsers |> Lightning.Policies.Permissions.can?(:edit_job, socket.assigns.current_user, socket.assigns.project)

  if can_edit_job do
    # allow user to edit the job
  else
    # quick user out
  end
  ```
  """
  def can(policy, action, user, params \\ []) do
    Bodyguard.permit(policy, action, user, params)
  end

  def can?(policy, action, user, params \\ []) do
    case can(policy, action, user, params) do
      :ok -> true
      {:error, :unauthorized} -> false
    end
  end
end
