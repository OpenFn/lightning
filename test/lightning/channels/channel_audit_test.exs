defmodule Lightning.Channels.ChannelAuditTest do
  use Lightning.DataCase, async: true

  import Ecto.Query

  alias Lightning.Auditing.Audit
  alias Lightning.Channels

  defp audit_events(channel_id) do
    Repo.all(
      from a in Audit,
        where: a.item_id == ^channel_id and a.item_type == "channel"
    )
  end

  defp filter_events(events, event_name),
    do: Enum.filter(events, &(&1.event == event_name))

  describe "destination auth method contract" do
    setup do
      %{user: insert(:user)}
    end

    test "cast_assoc auto-sets role for both client and destination", %{
      user: user
    } do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      pc = insert(:project_credential, project: project)

      # No "role" key in the params — the with: function should set it
      attrs = %{
        name: "both-auth",
        destination_url: "https://example.com",
        project_id: project.id,
        client_auth_methods: [%{webhook_auth_method_id: wam.id}],
        destination_auth_method: %{project_credential_id: pc.id}
      }

      {:ok, channel} = Channels.create_channel(attrs, actor: user)

      channel =
        Repo.preload(channel, [:client_auth_methods, :destination_auth_method])

      assert length(channel.client_auth_methods) == 1
      assert hd(channel.client_auth_methods).role == :client

      assert channel.destination_auth_method.role == :destination
      assert channel.destination_auth_method.project_credential_id == pc.id
    end

    test "destination_credential preloads through destination_auth_method" do
      project = insert(:project)
      pc = insert(:project_credential, project: project)
      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        webhook_auth_method: nil,
        project_credential: pc,
        role: :destination
      )

      channel = Repo.preload(channel, :destination_credential)

      assert channel.destination_credential.id == pc.id
    end

    # TODO: Remove the sink_url refutation once the rename migration has
    # been run everywhere — at that point the old column won't exist and
    # this negative assertion adds no value.
    test "audit 'created' event diff contains 'destination_url' not 'sink_url'",
         %{user: user} do
      project = insert(:project)

      {:ok, channel} =
        Channels.create_channel(
          %{
            name: "audit-field",
            destination_url: "https://example.com",
            project_id: project.id
          },
          actor: user
        )

      [audit] =
        audit_events(channel.id)
        |> filter_events("created")

      assert Map.has_key?(audit.changes.after, "destination_url")
      refute Map.has_key?(audit.changes.after, "sink_url")
    end
  end

  describe "auth_method audit events on create" do
    setup do
      %{user: insert(:user)}
    end

    test "emits 'auth_method_added' for client and destination auth methods",
         %{user: user} do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      pc = insert(:project_credential, project: project)

      # Create with client auth method
      {:ok, ch1} =
        Channels.create_channel(
          %{
            name: "with-client",
            destination_url: "https://example.com",
            project_id: project.id,
            client_auth_methods: [%{webhook_auth_method_id: wam.id}]
          },
          actor: user
        )

      [client_added] = filter_events(audit_events(ch1.id), "auth_method_added")

      assert client_added.changes.after == %{
               "role" => "client",
               "webhook_auth_method_id" => wam.id
             }

      # Create with destination auth method
      {:ok, ch2} =
        Channels.create_channel(
          %{
            name: "with-dest",
            destination_url: "https://example.com",
            project_id: project.id,
            destination_auth_method: %{project_credential_id: pc.id}
          },
          actor: user
        )

      [dest_added] = filter_events(audit_events(ch2.id), "auth_method_added")

      assert dest_added.changes.after == %{
               "role" => "destination",
               "project_credential_id" => pc.id
             }
    end

    test "does not emit auth method audit events when created with no auth methods",
         %{user: user} do
      project = insert(:project)

      {:ok, channel} =
        Channels.create_channel(
          %{
            name: "bare",
            destination_url: "https://example.com",
            project_id: project.id
          },
          actor: user
        )

      refute Enum.any?(
               audit_events(channel.id),
               &(&1.event in ["auth_method_added", "auth_method_removed"])
             )
    end
  end

  describe "auth_method audit events on update" do
    setup do
      %{user: insert(:user)}
    end

    test "emits 'auth_method_added' for client and destination auth methods",
         %{user: user} do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      pc = insert(:project_credential, project: project)

      # Add client auth method
      ch1 =
        insert(:channel, project: project)
        |> Repo.preload(:client_auth_methods)

      {:ok, _} =
        Channels.update_channel(
          ch1,
          %{"client_auth_methods" => [%{"webhook_auth_method_id" => wam.id}]},
          actor: user
        )

      [client_added] = filter_events(audit_events(ch1.id), "auth_method_added")

      assert %{
               changes: %{
                 after: %{"role" => "client", "webhook_auth_method_id" => wam_id},
                 before: nil
               }
             } = client_added

      assert wam_id == wam.id

      # Add destination auth method
      ch2 =
        insert(:channel, project: project)
        |> Repo.preload(:destination_auth_method)

      {:ok, _} =
        Channels.update_channel(
          ch2,
          %{"destination_auth_method" => %{"project_credential_id" => pc.id}},
          actor: user
        )

      [dest_added] = filter_events(audit_events(ch2.id), "auth_method_added")

      assert %{
               changes: %{
                 after: %{
                   "role" => "destination",
                   "project_credential_id" => pc_id
                 },
                 before: nil
               }
             } = dest_added

      assert pc_id == pc.id
    end

    test "emits 'auth_method_removed' for client and destination auth methods",
         %{user: user} do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      pc = insert(:project_credential, project: project)

      # Remove client auth method
      ch1 = insert(:channel, project: project)

      cam =
        insert(:channel_auth_method,
          channel: ch1,
          webhook_auth_method: wam,
          role: :client
        )

      ch1 = Repo.preload(ch1, :client_auth_methods)

      {:ok, _} =
        Channels.update_channel(
          ch1,
          %{"client_auth_methods" => [%{"id" => cam.id, "delete" => "true"}]},
          actor: user
        )

      [client_removed] =
        filter_events(audit_events(ch1.id), "auth_method_removed")

      assert %{
               changes: %{
                 before: %{
                   "role" => "client",
                   "webhook_auth_method_id" => wam_id
                 },
                 after: nil
               }
             } = client_removed

      assert wam_id == wam.id

      # Remove destination auth method
      ch2 = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: ch2,
        webhook_auth_method: nil,
        project_credential: pc,
        role: :destination
      )

      ch2 = Repo.preload(ch2, :destination_auth_method)

      {:ok, _} =
        Channels.update_channel(
          ch2,
          %{"destination_auth_method" => nil},
          actor: user
        )

      [dest_removed] =
        filter_events(audit_events(ch2.id), "auth_method_removed")

      assert %{
               changes: %{
                 before: %{
                   "role" => "destination",
                   "project_credential_id" => pc_id
                 },
                 after: nil
               }
             } = dest_removed

      assert pc_id == pc.id
    end

    test "swapping destination credential emits 'auth_method_changed'",
         %{user: user} do
      project = insert(:project)
      pc_old = insert(:project_credential, project: project)
      pc_new = insert(:project_credential, project: project)
      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        webhook_auth_method: nil,
        project_credential: pc_old,
        role: :destination
      )

      channel = Repo.preload(channel, :destination_auth_method)

      {:ok, _} =
        Channels.update_channel(
          channel,
          %{
            "destination_auth_method" => %{
              "project_credential_id" => pc_new.id
            }
          },
          actor: user
        )

      events = audit_events(channel.id)
      [changed] = filter_events(events, "auth_method_changed")

      pc_old_id = pc_old.id
      pc_new_id = pc_new.id

      assert %{
               before: %{
                 "role" => "destination",
                 "project_credential_id" => ^pc_old_id
               },
               after: %{
                 "role" => "destination",
                 "project_credential_id" => ^pc_new_id
               }
             } = changed.changes

      # TODO: Remove this refutation once the old two-event pattern is fully
      # gone — at that point added/removed won't fire for swaps and this
      # negative assertion adds no value.
      refute Enum.any?(
               events,
               &(&1.event in ["auth_method_added", "auth_method_removed"])
             )
    end

    test "does not emit auth method audit events when no auth methods change",
         %{user: user} do
      project = insert(:project)
      channel = insert(:channel, project: project)

      {:ok, _} =
        Channels.update_channel(channel, %{name: "new name"}, actor: user)

      refute Enum.any?(
               audit_events(channel.id),
               &(&1.event in ["auth_method_added", "auth_method_removed"])
             )
    end
  end
end
