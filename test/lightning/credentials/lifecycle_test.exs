defmodule Lightning.Credentials.LifecycleTest do
  use Lightning.DataCase, async: true

  import Lightning.RaceHelpers

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Projects.ProjectCredential

  defp operator do
    {account, _key} = Lightning.ServiceAccountHelpers.service_account_with_key()
    %{account | grants: MapSet.new(["credentials:write"])}
  end

  defp credential_with_bodies(owner) do
    insert(:credential, user: owner, schema: "raw")
    |> with_body(%{name: "staging", body: %{"a" => "s"}})
    |> with_body(%{name: "main", body: %{"a" => "m"}})
  end

  defp delete_mid_write(table, id) do
    after_first_query(table, id, fn id ->
      for child <- ~w(credential_bodies project_credentials) do
        Repo.query!("DELETE FROM #{child} WHERE credential_id = $1", [id])
      end

      Repo.query!("DELETE FROM credentials WHERE id = $1", [id])
    end)
  end

  describe "scheduling and cancelling a deletion" do
    test "a service account holding credentials:write may schedule and cancel anyone's" do
      credential = insert(:credential, user: insert(:user))

      assert {:ok, %Credential{scheduled_deletion: %DateTime{}} = scheduled} =
               Credentials.schedule_credential_deletion(credential, operator())

      assert {:ok, %Credential{scheduled_deletion: nil}} =
               Credentials.cancel_scheduled_deletion(scheduled, operator())
    end

    test "anyone else but the owner is refused both" do
      credential =
        insert(:credential,
          user: insert(:user),
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      stranger = insert(:user, role: :superuser)

      assert Credentials.cancel_scheduled_deletion(credential, stranger) ==
               {:error, :unauthorized}

      assert Credentials.cancel_scheduled_deletion(credential.id, stranger) ==
               {:error, :unauthorized}
    end

    test "a credential deleted mid-write is :concurrent_edit" do
      owner = insert(:user)
      credential = insert(:credential, user: owner)
      delete_mid_write("credentials", credential.id)

      assert Credentials.schedule_credential_deletion(
               Repo.reload!(credential),
               owner
             ) == {:error, :concurrent_edit}
    end

    test "of two requests scheduling at once, only the first schedules and emails; the second waits, then is :scheduled_for_deletion" do
      owner = insert(:user)
      credential = insert(:credential, user: owner)

      # The second request starts once the first has read the credential. It
      # gets 300ms to run to the end before the first carries on; it can't
      # while the first holds the row.
      after_first_query("credentials", credential.id, fn _id ->
        task =
          Task.async(fn ->
            Credentials.schedule_credential_deletion(credential, owner)
          end)

        Process.put(:second, Task.yield(task, 300) || task)
      end)

      assert {:ok, %Credential{scheduled_deletion: %DateTime{} = at}} =
               Credentials.schedule_credential_deletion(credential, owner)

      second =
        case Process.get(:second) do
          %Task{} = task -> Task.await(task)
          {:ok, result} -> result
        end

      assert second == {:error, :scheduled_for_deletion}

      assert DateTime.compare(Repo.reload!(credential).scheduled_deletion, at) ==
               :eq

      assert_received {:email, %Swoosh.Email{}}
      refute_received {:email, %Swoosh.Email{}}
    end
  end

  describe "environments" do
    test "list_environments/1 gives each name and its timestamps, by name, without bodies" do
      credential = credential_with_bodies(insert(:user))

      assert [
               %{name: "main", inserted_at: %DateTime{}, updated_at: %DateTime{}} =
                 main,
               %{name: "staging"}
             ] = Credentials.list_environments(credential)

      assert Map.keys(main) |> Enum.sort() == [:inserted_at, :name, :updated_at]
    end

    test "update_credential/3 is :concurrent_edit when the credential is deleted while only a body changes" do
      owner = insert(:user)
      credential = credential_with_bodies(owner)
      delete_mid_write("credentials", credential.id)

      assert Credentials.update_credential(
               credential,
               %{"credential_bodies" => [%{"name" => "prod", "body" => %{}}]},
               owner
             ) == {:error, :concurrent_edit}

      refute Repo.reload(credential)
    end
  end

  describe "project links" do
    setup do
      owner = insert(:user)
      admin = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :editor},
            %{user: admin, role: :admin}
          ]
        )

      credential = insert(:credential, user: owner)
      insert(:project_credential, project: project, credential: credential)

      %{owner: owner, admin: admin, project: project, credential: credential}
    end

    test "get_project_link/2 finds the link with its credential, or :not_found",
         %{project: project, credential: credential} do
      assert {:ok, %ProjectCredential{credential: %Credential{id: id}}} =
               Credentials.get_project_link(project.id, credential.id)

      assert id == credential.id

      assert Credentials.get_project_link(insert(:project).id, credential.id) ==
               {:error, :not_found}
    end

    test "unlink_credential/2 lets a project admin remove someone else's credential, recording removed_from_project",
         %{admin: admin, project: project, credential: credential} do
      {:ok, link} = Credentials.get_project_link(project.id, credential.id)

      assert {:ok, _link} = Credentials.unlink_credential(link, admin)

      assert Credentials.get_project_link(project.id, credential.id) ==
               {:error, :not_found}

      assert Repo.one!(
               from a in Lightning.Credentials.Audit.base_query(),
                 where:
                   a.item_id == ^credential.id and
                     a.event == "removed_from_project",
                 select: a.actor_id
             ) == admin.id
    end

    test "unlink_credential/2 refuses an editor who doesn't own the credential",
         %{project: project, credential: credential} do
      editor = insert(:user)
      insert(:project_user, project: project, user: editor, role: :editor)
      {:ok, link} = Credentials.get_project_link(project.id, credential.id)

      assert Credentials.unlink_credential(link, editor) ==
               {:error, :unauthorized}
    end

    test "unlink_credential/2 is :concurrent_edit when the link is already gone",
         %{owner: owner, project: project, credential: credential} do
      {:ok, link} = Credentials.get_project_link(project.id, credential.id)
      Repo.delete!(link)

      assert Credentials.unlink_credential(link, owner) ==
               {:error, :concurrent_edit}
    end
  end

  describe "transfers" do
    test "revoke_transfer/2 takes the credential itself" do
      owner = insert(:user)
      credential = insert(:credential, user: owner, transfer_status: :pending)

      assert {:ok, %Credential{transfer_status: nil}} =
               Credentials.revoke_transfer(credential, owner)

      assert Credentials.revoke_transfer(Repo.reload!(credential), owner) ==
               {:error, :not_pending}
    end

    test "a credential deleted mid-write is :concurrent_edit when starting or revoking" do
      owner = insert(:user)
      receiver = insert(:user)
      starting = insert(:credential, user: owner)
      revoking = insert(:credential, user: owner, transfer_status: :pending)

      Repo.delete!(starting)
      Repo.delete!(revoking)

      assert Credentials.initiate_credential_transfer(owner, receiver, starting) ==
               {:error, :concurrent_edit}

      assert Credentials.revoke_transfer(revoking, owner) ==
               {:error, :concurrent_edit}
    end
  end
end
