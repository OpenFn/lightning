defmodule Lightning.Channels.ChannelAuthMethodTest do
  use Lightning.DataCase, async: true

  alias Lightning.Channels.ChannelAuthMethod

  import Lightning.Factories

  describe "changeset/2" do
    test "valid source auth method with webhook_auth_method" do
      channel = insert(:channel)
      wam = insert(:webhook_auth_method, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :source,
          channel_id: channel.id,
          webhook_auth_method_id: wam.id
        })

      assert changeset.valid?
    end

    test "valid sink auth method with project_credential" do
      channel = insert(:channel)
      project_credential = insert(:project_credential, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :sink,
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
          role: :source,
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
          role: :source,
          channel_id: channel.id
        })

      refute changeset.valid?

      assert %{webhook_auth_method_id: [msg]} = errors_on(changeset)
      assert msg =~ "must reference either"
    end

    test "rejects source role with project_credential_id" do
      channel = insert(:channel)
      project_credential = insert(:project_credential, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :source,
          channel_id: channel.id,
          project_credential_id: project_credential.id
        })

      refute changeset.valid?

      assert %{project_credential_id: [msg]} = errors_on(changeset)
      assert msg =~ "source auth must use a webhook auth method"
    end

    test "rejects sink role with webhook_auth_method_id" do
      channel = insert(:channel)
      wam = insert(:webhook_auth_method, project: channel.project)

      changeset =
        ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{
          role: :sink,
          channel_id: channel.id,
          webhook_auth_method_id: wam.id
        })

      refute changeset.valid?

      assert %{webhook_auth_method_id: [msg]} = errors_on(changeset)
      assert msg =~ "sink auth must use a project credential"
    end

    test "requires role and channel_id" do
      changeset = ChannelAuthMethod.changeset(%ChannelAuthMethod{}, %{})

      refute changeset.valid?
      assert %{role: _, channel_id: _} = errors_on(changeset)
    end

    test "unique constraint on channel + role + webhook_auth_method_id" do
      channel = insert(:channel)
      wam = insert(:webhook_auth_method, project: channel.project)

      insert(:channel_auth_method,
        channel: channel,
        role: :source,
        webhook_auth_method: wam
      )

      assert {:error, changeset} =
               %ChannelAuthMethod{}
               |> ChannelAuthMethod.changeset(%{
                 role: :source,
                 channel_id: channel.id,
                 webhook_auth_method_id: wam.id
               })
               |> Lightning.Repo.insert()

      assert %{webhook_auth_method_id: _} = errors_on(changeset)
    end
  end
end
