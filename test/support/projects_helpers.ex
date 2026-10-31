defmodule Lightning.ProjectsHelpers do
  @moduledoc """
  Helpers for driving `Lightning.Projects` writes from tests.
  """

  import ExUnit.Assertions

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo

  @doc """
  Builds params for `Lightning.Projects.update_project_with_users/4` naming every
  current member of `project`.

  A membership write submits the whole member list: `cast_assoc/3` only sees the
  children the params name, and the one-owner validation runs over exactly
  those, so members nobody is touching still have to be named.

  `changes` maps a member — a `ProjectUser` or a `User` — to the role it takes;
  every other member is named by id alone. `new_members` are rows for people who
  are not members yet, each a map without an `:id`.

  Returns the project with its membership re-read alongside the params, because a
  caller's struct may carry an association that predates the rows being
  submitted, and `cast_assoc/3` matches the params against whatever the
  submitted struct has loaded.
  """
  @spec membership_params(Project.t(), map() | list(), [map()]) ::
          {Project.t(), map()}
  def membership_params(project, changes, new_members \\ []) do
    project = Repo.preload(project, :project_users, force: true)

    changes =
      Map.new(changes, fn {member, role} ->
        {project_user_id(project.project_users, member), role}
      end)

    members =
      Enum.map(project.project_users, fn %{id: id} ->
        case changes do
          %{^id => role} -> %{id: id, role: role}
          _ -> %{id: id}
        end
      end)

    {project, %{project_users: new_members ++ members}}
  end

  @doc """
  Turns off a project's support access as `actor`, returning the updated project.
  """
  def revoke_support_access(project, actor \\ nil) do
    {:ok, project} =
      Projects.update_project(project, %{allow_support_access: false}, actor)

    refute project.allow_support_access

    project
  end

  defp project_user_id(_members, %ProjectUser{id: id}), do: id

  defp project_user_id(members, %User{id: user_id}) do
    Enum.find_value(members, fn
      %{id: id, user_id: ^user_id} -> id
      _member -> nil
    end)
  end
end
