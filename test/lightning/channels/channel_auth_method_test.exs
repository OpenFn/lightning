defmodule Lightning.Channels.ChannelAuthMethodTest do
  use Lightning.DataCase, async: true

  alias Lightning.Channels.ChannelAuthMethod

  import Lightning.Factories

  describe "changeset/2" do
    test "valid client auth method with webhook_auth_method" do
      channel = insert(:channel)
      wam = insert(:webhook_auth_method, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :client,
          channel_id: channel.id,
          webhook_auth_method_id: wam.id
        })

      assert changeset.valid?
    end

    test "valid destination auth method with project_credential" do
      channel = insert(:channel)
      project_credential = insert(:project_credential, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :destination,
          channel_id: channel.id,
          project_credential_id: project_credential.id
        })

      assert changeset.valid?
    end

    test "rejects both FKs set (exclusive)" do
      channel = insert(:channel)
      wam = insert(:webhook_auth_method, project: channel.project)
      project_credential = insert(:project_credential, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :client,
          channel_id: channel.id,
          webhook_auth_method_id: wam.id,
          project_credential_id: project_credential.id
        })

      refute changeset.valid?

      assert %{webhook_auth_method_id: [msg]} = errors_on(changeset)
      assert msg =~ "mutually exclusive"
    end

    test "rejects neither FK set (one_required)" do
      channel = insert(:channel)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :client,
          channel_id: channel.id
        })

      refute changeset.valid?

      assert %{webhook_auth_method_id: [msg]} = errors_on(changeset)
      assert msg =~ "must reference either"
    end

    test "rejects client role with project_credential_id" do
      channel = insert(:channel)
      project_credential = insert(:project_credential, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :client,
          channel_id: channel.id,
          project_credential_id: project_credential.id
        })

      refute changeset.valid?

      assert %{project_credential_id: [msg]} = errors_on(changeset)
      assert msg =~ "client auth must use a webhook auth method"
    end

    test "rejects destination role with webhook_auth_method_id" do
      channel = insert(:channel)
      wam = insert(:webhook_auth_method, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :destination,
          channel_id: channel.id,
          webhook_auth_method_id: wam.id
        })

      refute changeset.valid?

      assert %{webhook_auth_method_id: [msg]} = errors_on(changeset)
      assert msg =~ "destination auth must use a project credential"
    end

    test "requires role" do
      changeset = ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{})

      refute changeset.valid?
      assert %{role: _} = errors_on(changeset)
    end

    test "unique constraint on channel + role + webhook_auth_method_id" do
      channel = insert(:channel)
      wam = insert(:webhook_auth_method, project: channel.project)

      insert(:channel_auth_method,
        channel: channel,
        role: :client,
        webhook_auth_method: wam
      )

      assert {:error, changeset} =
               %ChannelAuthMethod{channel_id: channel.id}
               |> ChannelAuthMethod.changeset(%{
                 role: :client,
                 webhook_auth_method_id: wam.id
               })
               |> Lightning.Repo.insert()

      assert %{webhook_auth_method_id: _} = errors_on(changeset)
    end

    test "partial unique index prevents second destination auth method per channel" do
      channel = insert(:channel)
      pc1 = insert(:project_credential, project: channel.project)
      pc2 = insert(:project_credential, project: channel.project)

      insert(:channel_auth_method,
        channel: channel,
        webhook_auth_method: nil,
        project_credential: pc1,
        role: :destination
      )

      assert {:error, changeset} =
               %ChannelAuthMethod{channel_id: channel.id}
               |> ChannelAuthMethod.changeset(%{
                 role: :destination,
                 project_credential_id: pc2.id
               })
               |> Lightning.Repo.insert()

      assert errors_on(changeset) != %{}
    end
  end
end
