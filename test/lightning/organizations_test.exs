defmodule Lightning.OrganizationsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Organizations
  alias Lightning.Organizations.OrganizationUser
  alias Lightning.Projects
  alias Lightning.Repo

  defp organization_with(members) do
    organization = insert(:organization)

    for {user, role} <- members,
        do:
          insert(:organization_user,
            organization: organization,
            user: user,
            role: role
          )

    organization
  end

  defp member(organization, user) do
    {:ok, member} = Organizations.fetch_member(organization.id, user.id)
    member
  end

  describe "an organization's admins" do
    test "the last admin can't be made a member or removed" do
      [admin, member] = insert_list(2, :user)
      organization = organization_with([{admin, :admin}, {member, :member}])

      assert Organizations.change_role(
               member(organization, admin),
               :member,
               admin
             ) ==
               {:error, :one_admin}

      assert Organizations.remove_member(member(organization, admin), admin) ==
               {:error, :one_admin}

      assert %OrganizationUser{role: :admin} =
               Repo.get_by(OrganizationUser, user_id: admin.id)
    end

    test "an admin steps down once another admin is there" do
      [first, second] = insert_list(2, :user)
      organization = organization_with([{first, :admin}, {second, :admin}])

      assert {:ok, %OrganizationUser{role: :member}} =
               Organizations.change_role(
                 member(organization, first),
                 :member,
                 first
               )

      assert Organizations.remove_member(member(organization, second), second) ==
               {:error, :one_admin}
    end

    test "a member removed by another request meanwhile is a concurrent edit" do
      [admin, member] = insert_list(2, :user)
      organization = organization_with([{admin, :admin}, {member, :member}])
      stale = member(organization, member)
      Repo.delete!(stale)

      assert Organizations.change_role(stale, :admin, admin) ==
               {:error, :concurrent_edit}

      assert Organizations.remove_member(stale, admin) ==
               {:error, :concurrent_edit}
    end
  end

  describe "membership and projects" do
    test "removing someone from an organization leaves their projects and account alone" do
      [admin, member] = insert_list(2, :user)
      organization = organization_with([{admin, :admin}, {member, :member}])

      project =
        insert(:project,
          organization: organization,
          project_users: [%{user: member, role: :editor}]
        )

      assert {:ok, _removed} =
               Organizations.remove_member(member(organization, member), admin)

      assert Projects.get_project_user_role(member, project) == :editor
      refute Repo.reload(member).disabled
    end

    test "a sandbox belongs to its parent's organization" do
      owner = insert(:user)
      organization = organization_with([{owner, :admin}])

      parent =
        insert(:project,
          organization: organization,
          project_users: [%{user: owner, role: :owner}]
        )

      assert {:ok, sandbox} =
               Lightning.Projects.Sandboxes.provision(parent, owner, %{
                 name: "staging"
               })

      assert sandbox.organization_id == organization.id
    end
  end

  describe "listing" do
    test "a person sees the organizations they belong to, with their role; all: true shows every one" do
      person = insert(:user)
      mine = organization_with([{person, :member}])
      other = organization_with([])

      assert %{entries: [found]} =
               Organizations.paginate_organizations(person, %{}, all: false)

      assert {found.id, found.role} == {mine.id, :member}

      assert %{entries: all} =
               Organizations.paginate_organizations(person, %{}, all: true)

      assert all |> Enum.map(&{&1.id, &1.role}) |> Enum.sort() ==
               Enum.sort([{mine.id, :member}, {other.id, nil}])
    end
  end
end
