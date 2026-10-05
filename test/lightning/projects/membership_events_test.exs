defmodule Lightning.Projects.MembershipEventsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing.Audit
  alias Lightning.Projects
  alias Lightning.Projects.Events
  alias Lightning.Projects.Events.ProjectUserAdded
  alias Lightning.Projects.Events.ProjectUserRemoved
  alias Lightning.Projects.Events.ProjectUserRoleChanged
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser

  setup do
    owner = insert(:user)
    member = insert(:user)
    actor = insert(:user)

    project =
      insert(:project,
        project_users: [
          %{user_id: owner.id, role: :owner},
          %{user_id: member.id, role: :editor}
        ]
      )

    assert :ok = Events.subscribe(project.id)

    %{
      project: project,
      owner: owner,
      member: member,
      actor: actor,
      owner_project_user: Projects.get_project_user(project, owner),
      member_project_user: Projects.get_project_user(project, member)
    }
  end

  describe "update_project_with_users/4" do
    test "broadcasts and audits one event per member it touches", %{
      project: %{id: project_id} = project,
      member: %{id: member_id},
      actor: %{id: actor_id} = actor,
      owner: %{id: owner_id},
      owner_project_user: owner_project_user,
      member_project_user: member_project_user
    } do
      %{id: joiner_id} = joiner = insert(:user)
      %{id: demoted_id} = demoted = insert(:user)

      demoted_project_user =
        insert(:project_user, project: project, user: demoted, role: :admin)

      project = Repo.preload(project, :project_users, force: true)

      assert {:ok, updated_project} =
               Projects.update_project_with_users(
                 project,
                 %{
                   project_users: [
                     %{id: owner_project_user.id},
                     %{id: member_project_user.id, delete: true},
                     %{id: demoted_project_user.id, role: :viewer},
                     %{user_id: joiner.id, role: :editor}
                   ]
                 },
                 actor,
                 false
               )

      # the returned struct reflects the post-update membership
      assert updated_project.project_users
             |> Enum.map(& &1.user_id)
             |> Enum.sort() == Enum.sort([owner_id, demoted_id, joiner_id])

      assert_receive %ProjectUserRemoved{
        project_id: ^project_id,
        user_id: ^member_id
      }

      assert_receive %ProjectUserRoleChanged{
        project_id: ^project_id,
        user_id: ^demoted_id
      }

      assert_receive %ProjectUserAdded{
        project_id: ^project_id,
        user_id: ^joiner_id
      }

      # the owner row was submitted unchanged
      refute_received %ProjectUserAdded{user_id: ^owner_id}
      refute_received %ProjectUserRemoved{user_id: ^owner_id}
      refute_received %ProjectUserRoleChanged{user_id: ^owner_id}

      assert %{
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^actor_id,
               changes: %Audit.Changes{
                 before: nil,
                 after: %{"user_id" => ^joiner_id, "role" => "editor"}
               }
             } = Repo.get_by!(Audit, event: "collaborator_added")

      assert %{
               item_id: ^project_id,
               actor_id: ^actor_id,
               changes: %Audit.Changes{
                 before: %{"user_id" => ^demoted_id, "role" => "admin"},
                 after: %{"user_id" => ^demoted_id, "role" => "viewer"}
               }
             } = Repo.get_by!(Audit, event: "collaborator_role_changed")

      assert %{
               item_id: ^project_id,
               actor_id: ^actor_id,
               changes: %Audit.Changes{
                 before: %{"user_id" => ^member_id, "role" => "editor"},
                 after: nil
               }
             } = Repo.get_by!(Audit, event: "collaborator_removed")

      assert audit_count(project_id) == 3
    end

    test "broadcasts and audits nothing when membership is resubmitted unchanged",
         %{
           project: %{id: project_id} = project,
           actor: actor,
           owner_project_user: owner_project_user,
           member_project_user: member_project_user
         } do
      assert {:ok, _project} =
               Projects.update_project_with_users(
                 project,
                 %{
                   project_users: [
                     %{id: owner_project_user.id},
                     %{id: member_project_user.id, digest: :weekly}
                   ]
                 },
                 actor,
                 false
               )

      refute_receive %ProjectUserAdded{}
      refute_receive %ProjectUserRemoved{}
      refute_receive %ProjectUserRoleChanged{}

      assert audit_count(project_id) == 0
    end

    test "revokes the leaving user's project credentials", %{
      project: %{id: project_id} = project,
      owner: owner,
      member: %{id: member_id} = member,
      actor: actor,
      owner_project_user: owner_project_user,
      member_project_user: member_project_user
    } do
      member_credential =
        insert(:credential,
          user: member,
          project_credentials: [%{project_id: project.id}]
        )

      owner_credential =
        insert(:credential,
          user: owner,
          project_credentials: [%{project_id: project.id}]
        )

      other_project = insert(:project)

      elsewhere_credential =
        insert(:credential,
          user: member,
          project_credentials: [%{project_id: other_project.id}]
        )

      assert {:ok, _project} =
               Projects.update_project_with_users(
                 project,
                 %{
                   project_users: [
                     %{id: owner_project_user.id},
                     %{id: member_project_user.id, delete: true}
                   ]
                 },
                 actor,
                 false
               )

      refute project_credential(project.id, member_credential)
      assert project_credential(project.id, owner_credential)
      assert project_credential(other_project.id, elsewhere_credential)

      # only the link is revoked, the credential itself survives
      assert Repo.get(Lightning.Credentials.Credential, member_credential.id)

      assert %{
               item_id: ^project_id,
               changes: %Audit.Changes{
                 before: %{"user_id" => ^member_id, "role" => "editor"},
                 after: nil
               }
             } = Repo.get_by!(Audit, event: "collaborator_removed")

      assert_receive %ProjectUserRemoved{
        project_id: ^project_id,
        user_id: ^member_id
      }
    end

    test "refuses to delete-mark the project owner", %{
      project: %{id: project_id} = project,
      actor: actor,
      owner_project_user: owner_project_user,
      member_project_user: member_project_user
    } do
      assert {:error, changeset} =
               Projects.update_project_with_users(
                 project,
                 %{
                   project_users: [
                     %{id: owner_project_user.id, delete: true},
                     %{id: member_project_user.id}
                   ]
                 },
                 actor,
                 false
               )

      assert %{
               owner: [
                 "Every project must have exactly one owner. Please specify one below."
               ]
             } = errors_on(changeset)

      assert Repo.get(ProjectUser, owner_project_user.id)
      refute_receive %ProjectUserRemoved{}
      assert audit_count(project_id) == 0
    end
  end

  describe "add_project_users/4" do
    test "broadcasts and audits the new member only", %{
      project: %{id: project_id} = project,
      owner: %{id: owner_id},
      member: %{id: member_id},
      actor: %{id: actor_id} = actor
    } do
      %{id: joiner_id} = joiner = insert(:user)

      assert {:ok, _project_users} =
               Projects.add_project_users(
                 project,
                 [%{user_id: joiner.id, role: :viewer}],
                 actor,
                 false
               )

      assert_receive %ProjectUserAdded{
        project_id: ^project_id,
        user_id: ^joiner_id
      }

      refute_received %ProjectUserAdded{user_id: ^owner_id}
      refute_received %ProjectUserAdded{user_id: ^member_id}
      refute_received %ProjectUserRoleChanged{}
      refute_received %ProjectUserRemoved{}

      assert %{
               item_id: ^project_id,
               actor_id: ^actor_id,
               changes: %Audit.Changes{
                 before: nil,
                 after: %{"user_id" => ^joiner_id, "role" => "viewer"}
               }
             } = Repo.get_by!(Audit, event: "collaborator_added")

      assert audit_count(project_id) == 1
    end
  end

  describe "delete_project_user!/2" do
    test "broadcasts and audits the removal against the actor", %{
      project: %{id: project_id},
      member: %{id: member_id},
      actor: %{id: actor_id} = actor,
      member_project_user: member_project_user
    } do
      Projects.delete_project_user!(member_project_user, actor)

      assert_receive %ProjectUserRemoved{
        project_id: ^project_id,
        user_id: ^member_id
      }

      assert %{
               item_type: "project",
               item_id: ^project_id,
               actor_id: ^actor_id,
               changes: %Audit.Changes{
                 before: %{"user_id" => ^member_id, "role" => "editor"},
                 after: nil
               }
             } = Repo.get_by!(Audit, event: "collaborator_removed")

      assert audit_count(project_id) == 1
    end
  end

  describe "invite_collaborators/3" do
    test "broadcasts and audits the addition against the inviter", %{
      project: %{id: project_id} = project,
      owner: %{id: inviter_id} = inviter
    } do
      assert {:ok, _result} =
               Projects.invite_collaborators(project, [invitee()], inviter)

      assert %{
               item_id: ^project_id,
               actor_id: ^inviter_id,
               changes: %Audit.Changes{
                 before: nil,
                 after: %{"role" => "editor"}
               }
             } = Repo.get_by!(Audit, event: "collaborator_added")

      assert_receive %ProjectUserAdded{project_id: ^project_id}
    end

    test "publishes nothing when a later step rolls the transaction back", %{
      project: %{id: project_id} = project,
      owner: inviter
    } do
      # The invitation email is delivered from inside the transaction; a failure
      # there must take the membership, its audit trail and its broadcast with
      # it.
      Mox.expect(Lightning.MockConfig, :email_sender_name, fn ->
        raise "mailer unavailable"
      end)

      assert_raise RuntimeError, "mailer unavailable", fn ->
        Projects.invite_collaborators(project, [invitee()], inviter)
      end

      refute_receive %ProjectUserAdded{}
      assert audit_count(project_id) == 0
      assert Repo.aggregate(ProjectUser, :count) == 2
    end
  end

  defp invitee do
    %{
      first_name: "New",
      last_name: "Person",
      email: "new.person@example.com",
      role: :editor
    }
  end

  defp audit_count(project_id) do
    Repo.aggregate(from(a in Audit, where: a.item_id == ^project_id), :count)
  end

  defp project_credential(project_id, credential) do
    Repo.get_by(ProjectCredential,
      project_id: project_id,
      credential_id: credential.id
    )
  end
end
