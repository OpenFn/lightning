defmodule Lightning.ChannelsTest do
  use Lightning.DataCase, async: true

  import Ecto.Query

  alias Lightning.Auditing.Audit
  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelAuthMethod
  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Channels.ChannelSnapshot
  alias Lightning.Channels.SearchParams
  alias Lightning.Projects.Project

  describe "list_channels_for_project/1" do
    test "returns channels for a project ordered by name" do
      project = insert(:project)
      insert(:channel, project: project, name: "bravo")
      insert(:channel, project: project, name: "alpha")
      insert(:channel, project: build(:project), name: "other")

      channels = Channels.list_channels_for_project(project.id)

      assert length(channels) == 2
      assert [%Channel{name: "alpha"}, %Channel{name: "bravo"}] = channels
    end

    test "returns empty list when project has no channels" do
      project = insert(:project)
      assert Channels.list_channels_for_project(project.id) == []
    end
  end

  describe "list_channels_for_project_with_stats/1" do
    test "returns empty list for project with no channels" do
      project = insert(:project)

      assert Channels.list_channels_for_project_with_stats(project.id) == []
    end

    test "returns correct request_count and last_activity for a channel with requests" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      t1 = ~U[2025-01-01 10:00:00.000000Z]
      t2 = ~U[2025-01-02 12:00:00.000000Z]

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-stats-1",
        state: :success,
        started_at: t1
      })

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "req-stats-2",
        state: :success,
        started_at: t2
      })

      results = Channels.list_channels_for_project_with_stats(project.id)

      assert [
               %{
                 channel: %Channel{id: channel_id},
                 request_count: 2,
                 last_activity: ^t2
               }
             ] = results

      assert channel_id == channel.id
    end

    test "last_activity is nil when no requests exist" do
      project = insert(:project)
      insert(:channel, project: project)

      [result] = Channels.list_channels_for_project_with_stats(project.id)

      assert %{request_count: 0, last_activity: nil} = result
    end

    test "returns multiple channels ordered by name with independent stats" do
      project = insert(:project)
      channel_b = insert(:channel, project: project, name: "bravo")
      channel_a = insert(:channel, project: project, name: "alpha")

      {:ok, snapshot_b} = Channels.get_or_create_current_snapshot(channel_b)

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel_b.id,
        channel_snapshot_id: snapshot_b.id,
        request_id: "req-stats-3",
        state: :success,
        started_at: ~U[2025-06-01 00:00:00.000000Z]
      })

      results = Channels.list_channels_for_project_with_stats(project.id)

      assert [
               %{channel: %Channel{name: "alpha"}, request_count: 0},
               %{channel: %Channel{name: "bravo"}, request_count: 1}
             ] = results

      assert Enum.find(results, &(&1.channel.id == channel_a.id)).last_activity ==
               nil
    end

    test "excludes channels from other projects" do
      project = insert(:project)
      other_project = insert(:project)
      insert(:channel, project: project, name: "mine")
      insert(:channel, project: other_project, name: "theirs")

      results = Channels.list_channels_for_project_with_stats(project.id)

      assert length(results) == 1
      assert hd(results).channel.name == "mine"
    end
  end

  describe "get_channel!/1" do
    test "returns the channel" do
      channel = insert(:channel)
      assert Channels.get_channel!(channel.id).id == channel.id
    end

    test "raises on not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_channel/2" do
    setup do
      %{user: insert(:user)}
    end

    test "emits 'auth_method_added' for client auth method on create", %{
      user: user
    } do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)

      attrs = %{
        name: "my channel",
        destination_url: "https://example.com",
        project_id: project.id,
        client_auth_methods: [
          %{webhook_auth_method_id: wam.id}
        ]
      }

      {:ok, channel} = Channels.create_channel(attrs, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      added = Enum.filter(events, &(&1.event == "auth_method_added"))

      assert length(added) == 1

      assert hd(added).changes.after == %{
               "role" => "client",
               "webhook_auth_method_id" => wam.id
             }
    end

    test "emits 'auth_method_added' for destination auth method on create", %{
      user: user
    } do
      project = insert(:project)
      pc = insert(:project_credential, project: project)

      attrs = %{
        name: "my channel",
        destination_url: "https://example.com",
        project_id: project.id,
        destination_auth_method: %{project_credential_id: pc.id}
      }

      {:ok, channel} = Channels.create_channel(attrs, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      added = Enum.filter(events, &(&1.event == "auth_method_added"))

      assert length(added) == 1

      assert hd(added).changes.after == %{
               "role" => "destination",
               "project_credential_id" => pc.id
             }
    end

    test "does not emit auth method audit events when created with no auth methods",
         %{user: user} do
      project = insert(:project)

      attrs = %{
        name: "bare",
        destination_url: "https://example.com",
        project_id: project.id
      }

      {:ok, channel} = Channels.create_channel(attrs, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      refute Enum.any?(
               events,
               &(&1.event in ["auth_method_added", "auth_method_removed"])
             )
    end

    test "creates a channel with valid attrs and records audit event", %{
      user: user
    } do
      project = insert(:project)

      assert {:ok, %Channel{} = channel} =
               Channels.create_channel(
                 %{
                   name: "my-channel",
                   destination_url: "https://example.com/sink",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{
               name: "my-channel",
               enabled: true,
               lock_version: 1
             } = channel

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where: a.item_id == ^channel.id and a.item_type == "channel"
               )

      assert %{event: "created", actor_id: actor_id} = audit
      assert actor_id == user.id
    end

    test "returns error on missing required fields", %{user: user} do
      assert {:error, changeset} =
               Channels.create_channel(%{}, actor: user)

      assert %{name: _, destination_url: _, project_id: _} = errors_on(changeset)
    end

    test "returns error for non-URL destination_url", %{user: user} do
      project = insert(:project)

      assert {:error, changeset} =
               Channels.create_channel(
                 %{
                   name: "bad-sink",
                   destination_url: "not a url",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{destination_url: ["must be a valid URL"]} = errors_on(changeset)
    end

    test "returns error for non-http scheme destination_url", %{user: user} do
      project = insert(:project)

      assert {:error, changeset} =
               Channels.create_channel(
                 %{
                   name: "ftp-sink",
                   destination_url: "ftp://example.com",
                   project_id: project.id
                 },
                 actor: user
               )

      assert %{destination_url: ["must be either a http or https URL"]} =
               errors_on(changeset)
    end

    test "accepts valid http and https destination_urls", %{user: user} do
      project = insert(:project)

      assert {:ok, _} =
               Channels.create_channel(
                 %{
                   name: "http-sink",
                   destination_url: "http://example.com/path",
                   project_id: project.id
                 },
                 actor: user
               )

      assert {:ok, _} =
               Channels.create_channel(
                 %{
                   name: "https-sink",
                   destination_url: "https://example.com/path",
                   project_id: project.id
                 },
                 actor: user
               )
    end

    test "returns error on duplicate name within project", %{user: user} do
      channel = insert(:channel)

      assert {:error, changeset} =
               Channels.create_channel(
                 %{
                   name: channel.name,
                   destination_url: "https://example.com/other",
                   project_id: channel.project_id
                 },
                 actor: user
               )

      assert %{name: ["A channel with this name already exists in this project"]} =
               errors_on(changeset)
    end
  end

  describe "update_channel/3" do
    setup do
      %{user: insert(:user)}
    end

    test "emits 'auth_method_added' for each added client auth method", %{
      user: user
    } do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)

      channel =
        insert(:channel, project: project)
        |> Repo.preload(:client_auth_methods)

      params = %{
        "client_auth_methods" => [
          %{"webhook_auth_method_id" => wam.id}
        ]
      }

      {:ok, _} = Channels.update_channel(channel, params, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      added = Enum.filter(events, &(&1.event == "auth_method_added"))

      assert length(added) == 1

      assert %{
               changes: %{
                 after: %{"role" => "client", "webhook_auth_method_id" => wam_id},
                 before: nil
               }
             } = hd(added)

      assert wam_id == wam.id
    end

    test "emits 'auth_method_added' when setting destination auth method", %{
      user: user
    } do
      project = insert(:project)
      pc = insert(:project_credential, project: project)

      channel =
        insert(:channel, project: project)
        |> Repo.preload(:destination_auth_method)

      params = %{
        "destination_auth_method" => %{"project_credential_id" => pc.id}
      }

      {:ok, _} = Channels.update_channel(channel, params, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      added = Enum.filter(events, &(&1.event == "auth_method_added"))

      assert length(added) == 1

      assert %{
               changes: %{
                 after: %{
                   "role" => "destination",
                   "project_credential_id" => pc_id
                 },
                 before: nil
               }
             } = hd(added)

      assert pc_id == pc.id
    end

    test "emits 'auth_method_removed' for each removed client auth method", %{
      user: user
    } do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      channel = insert(:channel, project: project)

      cam =
        insert(:channel_auth_method,
          channel: channel,
          webhook_auth_method: wam,
          role: :client
        )

      channel = Repo.preload(channel, :client_auth_methods)

      params = %{
        "client_auth_methods" => [
          %{"id" => cam.id, "delete" => "true"}
        ]
      }

      {:ok, _} = Channels.update_channel(channel, params, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      removed = Enum.filter(events, &(&1.event == "auth_method_removed"))

      assert length(removed) == 1

      assert %{
               changes: %{
                 before: %{
                   "role" => "client",
                   "webhook_auth_method_id" => wam_id
                 },
                 after: nil
               }
             } = hd(removed)

      assert wam_id == wam.id
    end

    test "emits 'auth_method_removed' when clearing destination auth method", %{
      user: user
    } do
      project = insert(:project)
      pc = insert(:project_credential, project: project)
      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        webhook_auth_method: nil,
        project_credential: pc,
        role: :destination
      )

      channel = Repo.preload(channel, :destination_auth_method)

      # Passing nil clears the has_one; on_replace: :delete removes the record
      params = %{"destination_auth_method" => nil}

      {:ok, _} = Channels.update_channel(channel, params, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      removed = Enum.filter(events, &(&1.event == "auth_method_removed"))

      assert length(removed) == 1

      assert %{
               changes: %{
                 before: %{
                   "role" => "destination",
                   "project_credential_id" => pc_id
                 },
                 after: nil
               }
             } = hd(removed)

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

      params = %{
        "destination_auth_method" => %{"project_credential_id" => pc_new.id}
      }

      {:ok, _} = Channels.update_channel(channel, params, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      changed = Enum.filter(events, &(&1.event == "auth_method_changed"))

      assert length(changed) == 1

      assert hd(changed).changes == %{
               before: %{
                 "role" => "destination",
                 "project_credential_id" => pc_old.id
               },
               after: %{
                 "role" => "destination",
                 "project_credential_id" => pc_new.id
               }
             }

      # TODO: Remove this refutation once the old two-event pattern is fully
      # gone — at that point added/removed won't fire for swaps and this
      # negative assertion adds no value.
      refute Enum.any?(
               events,
               &(&1.event in ["auth_method_added", "auth_method_removed"])
             )
    end

    test "does not emit auth method audit events when no auth methods change", %{
      user: user
    } do
      project = insert(:project)
      channel = insert(:channel, project: project)

      {:ok, _} =
        Channels.update_channel(channel, %{name: "new name"}, actor: user)

      events =
        Repo.all(
          from a in Audit,
            where: a.item_id == ^channel.id and a.item_type == "channel"
        )

      refute Enum.any?(
               events,
               &(&1.event in ["auth_method_added", "auth_method_removed"])
             )
    end

    test "updates config fields, bumps lock_version, and records audit event",
         %{user: user} do
      channel = insert(:channel)

      assert {:ok, updated} =
               Channels.update_channel(channel, %{name: "new-name"}, actor: user)

      assert %{name: "new-name", lock_version: lock_version} = updated
      assert lock_version == channel.lock_version + 1

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel.id and a.item_type == "channel" and
                       a.event == "updated"
               )

      assert audit.actor_id == user.id
    end

    test "returns stale error on lock_version conflict", %{user: user} do
      channel = insert(:channel)

      # Simulate concurrent update by updating lock_version in DB
      {1, _} =
        Lightning.Repo.update_all(
          from(c in Channel, where: c.id == ^channel.id),
          set: [lock_version: channel.lock_version + 1]
        )

      assert {:error, changeset} =
               Channels.update_channel(channel, %{name: "stale-update"},
                 actor: user
               )

      assert changeset.errors[:lock_version]
    end
  end

  describe "delete_channel/2" do
    setup do
      %{user: insert(:user)}
    end

    test "deletes a channel with no snapshots and records audit event", %{
      user: user
    } do
      channel = insert(:channel)
      channel_id = channel.id

      assert {:ok, %Channel{}} = Channels.delete_channel(channel, actor: user)

      assert_raise Ecto.NoResultsError, fn ->
        Channels.get_channel!(channel_id)
      end

      assert [audit] =
               Repo.all(
                 from a in Audit,
                   where:
                     a.item_id == ^channel_id and a.item_type == "channel" and
                       a.event == "deleted"
               )

      assert audit.actor_id == user.id
    end

    test "cascade deletes associated snapshots", %{user: user} do
      channel = insert(:channel)
      snapshot = insert(:channel_snapshot, channel: channel)

      assert {:ok, %Channel{}} = Channels.delete_channel(channel, actor: user)

      refute Repo.get(ChannelSnapshot, snapshot.id)
    end
  end

  describe "get_channel_with_auth/1" do
    test "returns channel with preloaded client auth methods" do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :client,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "test-key"
                )
            )
          ]
        )

      result = Channels.get_channel_with_auth(channel.id)

      assert result.id == channel.id
      assert length(result.client_auth_methods) == 1

      [cam] = result.client_auth_methods
      assert cam.role == :client
      assert cam.webhook_auth_method.auth_type == :api
      assert cam.webhook_auth_method.api_key == "test-key"
    end

    test "returns channel with preloaded destination auth method" do
      project = insert(:project)
      pc = insert(:project_credential, project: project)

      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        webhook_auth_method: nil,
        project_credential: pc,
        role: :destination
      )

      result = Channels.get_channel_with_auth(channel.id)

      assert result.destination_auth_method.role == :destination
      assert result.destination_auth_method.project_credential.id == pc.id
    end

    test "returns channel with empty client_auth_methods when none configured" do
      channel = insert(:channel)

      result = Channels.get_channel_with_auth(channel.id)

      assert result.id == channel.id
      assert result.client_auth_methods == []
      assert result.destination_auth_method == nil
    end

    test "returns nil for non-existent channel" do
      assert Channels.get_channel_with_auth(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_channel_auth_methods/1" do
    test "returns empty list for a channel with no auth methods" do
      channel = insert(:channel)
      assert Channels.list_channel_auth_methods(channel) == []
    end

    test "returns preloaded client and destination records for a channel with both" do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      pc = insert(:project_credential, project: project)

      channel =
        insert(:channel,
          project: project,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :client,
              webhook_auth_method: wam
            ),
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: pc
            )
          ]
        )

      cams = Channels.list_channel_auth_methods(channel)

      assert length(cams) == 2

      client = Enum.find(cams, &(&1.role == :client))
      destination = Enum.find(cams, &(&1.role == :destination))

      assert %ChannelAuthMethod{
               role: :client,
               webhook_auth_method_id: wam_id,
               webhook_auth_method: %{id: preloaded_wam_id}
             } = client

      assert wam_id == wam.id
      assert preloaded_wam_id == wam.id

      assert %ChannelAuthMethod{
               role: :destination,
               project_credential_id: pc_id,
               project_credential: %{id: preloaded_pc_id}
             } = destination

      assert pc_id == pc.id
      assert preloaded_pc_id == pc.id
    end
  end

  describe "get_channel_stats_for_project/1" do
    test "returns zeros for a project with no channels" do
      project = insert(:project)

      assert %{total_channels: 0, total_requests: 0} =
               Channels.get_channel_stats_for_project(project.id)
    end

    test "counts channels correctly" do
      project = insert(:project)
      insert(:channel, project: project)
      insert(:channel, project: project)

      assert %{total_channels: 2} =
               Channels.get_channel_stats_for_project(project.id)
    end

    test "sums requests across all channels" do
      project = insert(:project)
      channel1 = insert(:channel, project: project)
      channel2 = insert(:channel, project: project)
      {:ok, snapshot1} = Channels.get_or_create_current_snapshot(channel1)
      {:ok, snapshot2} = Channels.get_or_create_current_snapshot(channel2)

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel1.id,
        channel_snapshot_id: snapshot1.id,
        request_id: "stats-r1",
        state: :success,
        started_at: DateTime.utc_now()
      })

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel1.id,
        channel_snapshot_id: snapshot1.id,
        request_id: "stats-r2",
        state: :success,
        started_at: DateTime.utc_now()
      })

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: channel2.id,
        channel_snapshot_id: snapshot2.id,
        request_id: "stats-r3",
        state: :success,
        started_at: DateTime.utc_now()
      })

      assert %{total_requests: 3} =
               Channels.get_channel_stats_for_project(project.id)
    end

    test "does not count requests from other projects" do
      project = insert(:project)
      other_channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(other_channel)

      Lightning.Repo.insert!(%ChannelRequest{
        channel_id: other_channel.id,
        channel_snapshot_id: snapshot.id,
        request_id: "stats-other-r1",
        state: :success,
        started_at: DateTime.utc_now()
      })

      assert %{total_requests: 0} =
               Channels.get_channel_stats_for_project(project.id)
    end
  end

  describe "SearchParams.new/1" do
    test "returns struct with nil channel_id for empty map" do
      assert %SearchParams{channel_id: nil} = SearchParams.new(%{})
    end

    test "accepts a valid UUID string under the 'channel_id' key" do
      uuid = Ecto.UUID.generate()

      assert %SearchParams{channel_id: ^uuid} =
               SearchParams.new(%{"channel_id" => uuid})
    end

    test "silently drops an invalid UUID, leaving channel_id as nil" do
      assert %SearchParams{channel_id: nil} =
               SearchParams.new(%{"channel_id" => "not-a-uuid"})
    end

    test "silently drops unknown keys" do
      assert %SearchParams{channel_id: nil} =
               SearchParams.new(%{"unknown_key" => "value"})
    end
  end

  describe "list_channel_requests/3" do
    setup do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      %{project: project, channel: channel, snapshot: snapshot}
    end

    defp insert_request(channel, snapshot, attrs \\ []) do
      insert(
        :channel_request,
        [channel: channel, channel_snapshot: snapshot, state: :success] ++ attrs
      )
    end

    defp insert_event(request, attrs) do
      insert(:channel_event, [channel_request: request] ++ attrs)
    end

    test "returns a Scrivener.Page scoped to the given project", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      insert_request(channel, snapshot)
      other_channel = insert(:channel)

      {:ok, other_snapshot} =
        Channels.get_or_create_current_snapshot(other_channel)

      insert_request(other_channel, other_snapshot)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert %Scrivener.Page{entries: [%ChannelRequest{}]} = page
      assert page.total_entries == 1
    end

    test "excludes requests belonging to other projects", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      _mine = insert_request(channel, snapshot)

      other_channel = insert(:channel)

      {:ok, other_snapshot} =
        Channels.get_or_create_current_snapshot(other_channel)

      _theirs = insert_request(other_channel, other_snapshot)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert page.total_entries == 1
      [entry] = page.entries
      assert entry.channel_id == channel.id
    end

    test "filters by channel_id when provided", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      channel_b = insert(:channel, project: project)
      {:ok, snapshot_b} = Channels.get_or_create_current_snapshot(channel_b)

      insert_request(channel, snapshot)
      insert_request(channel_b, snapshot_b)

      params = SearchParams.new(%{"channel_id" => channel.id})
      page = Channels.list_channel_requests(project, params)

      assert page.total_entries == 1
      assert hd(page.entries).channel_id == channel.id
    end

    test "returns all project requests when no channel_id filter", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      channel_b = insert(:channel, project: project)
      {:ok, snapshot_b} = Channels.get_or_create_current_snapshot(channel_b)

      insert_request(channel, snapshot)
      insert_request(channel_b, snapshot_b)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert page.total_entries == 2
    end

    test "preloads :channel association on each entry", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      insert_request(channel, snapshot)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert [%ChannelRequest{channel: %Channel{id: channel_id}}] = page.entries
      assert channel_id == channel.id
    end

    test "preloads :channel_events with only :sink_response and :error types",
         %{project: project, channel: channel, snapshot: snapshot} do
      request = insert_request(channel, snapshot)

      insert_event(request, type: :sink_response, request_path: "/outbound")
      insert_event(request, type: :error, error_message: "timeout")

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      [entry] = page.entries

      assert length(entry.channel_events) == 2

      assert Enum.all?(
               entry.channel_events,
               &(&1.type in [:sink_response, :error])
             )

      sink_event =
        Enum.find(entry.channel_events, &(&1.type == :sink_response))

      error_event = Enum.find(entry.channel_events, &(&1.type == :error))

      assert %{request_path: "/outbound"} = sink_event
      assert %{error_message: "timeout"} = error_event
    end

    test "entries are ordered by started_at descending", %{
      project: project,
      channel: channel,
      snapshot: snapshot
    } do
      t1 = ~U[2025-01-01 10:00:00.000000Z]
      t2 = ~U[2025-01-02 10:00:00.000000Z]

      insert_request(channel, snapshot, started_at: t1)
      insert_request(channel, snapshot, started_at: t2)

      page = Channels.list_channel_requests(project, SearchParams.new(%{}))

      assert [first, second] = page.entries
      assert first.started_at == t2
      assert second.started_at == t1
    end
  end

  describe "get_or_create_current_snapshot/1" do
    setup do
      %{user: insert(:user)}
    end

    test "creates snapshot on first call" do
      channel = insert(:channel)

      assert {:ok, %ChannelSnapshot{} = snapshot} =
               Channels.get_or_create_current_snapshot(channel)

      assert snapshot.channel_id == channel.id
      assert snapshot.lock_version == channel.lock_version
      assert snapshot.name == channel.name
      assert snapshot.destination_url == channel.destination_url
      assert snapshot.enabled == channel.enabled
    end

    test "returns existing snapshot on same lock_version" do
      channel = insert(:channel)

      {:ok, snapshot1} = Channels.get_or_create_current_snapshot(channel)
      {:ok, snapshot2} = Channels.get_or_create_current_snapshot(channel)

      assert snapshot1.id == snapshot2.id
    end

    test "creates new snapshot on different lock_version", %{user: user} do
      channel = insert(:channel)
      {:ok, snapshot1} = Channels.get_or_create_current_snapshot(channel)

      {:ok, updated} =
        Channels.update_channel(channel, %{name: "updated-name"}, actor: user)

      {:ok, snapshot2} = Channels.get_or_create_current_snapshot(updated)

      assert snapshot1.id != snapshot2.id
      assert snapshot2.lock_version == updated.lock_version
      assert snapshot2.name == "updated-name"
    end
  end

  describe "delete_expired_requests/2" do
    test "deletes requests older than retention period" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      old_request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          started_at: Lightning.current_time() |> Timex.shift(days: -8)
        )

      recent_request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          started_at: Lightning.current_time() |> Timex.shift(days: -6)
        )

      assert :ok = Channels.delete_expired_requests(project.id, 7)

      refute Repo.get(ChannelRequest, old_request.id)
      assert Repo.get(ChannelRequest, recent_request.id)
    end

    test "cascades deletion to channel_events" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      old_request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          started_at: Lightning.current_time() |> Timex.shift(days: -8)
        )

      recent_request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          started_at: Lightning.current_time() |> Timex.shift(days: -6)
        )

      old_event =
        insert(:channel_event,
          channel_request: old_request,
          type: :sink_response
        )

      recent_event =
        insert(:channel_event,
          channel_request: recent_request,
          type: :sink_response
        )

      assert :ok = Channels.delete_expired_requests(project.id, 7)

      refute Repo.get(ChannelEvent, old_event.id)
      assert Repo.get(ChannelEvent, recent_event.id)
    end

    test "cleans up orphaned channel_snapshots" do
      user = insert(:user)
      project = insert(:project)
      channel = insert(:channel, project: project)

      {:ok, old_snapshot} =
        Channels.get_or_create_current_snapshot(channel)

      {:ok, updated_channel} =
        Channels.update_channel(channel, %{name: "updated"}, actor: user)

      {:ok, current_snapshot} =
        Channels.get_or_create_current_snapshot(updated_channel)

      # Old request referencing the old snapshot
      insert(:channel_request,
        channel: channel,
        channel_snapshot: old_snapshot,
        started_at: Lightning.current_time() |> Timex.shift(days: -8)
      )

      # Recent request referencing the current snapshot
      insert(:channel_request,
        channel: channel,
        channel_snapshot: current_snapshot,
        started_at: Lightning.current_time() |> Timex.shift(days: -6)
      )

      assert :ok = Channels.delete_expired_requests(project.id, 7)

      # Old snapshot is orphaned (no remaining requests, lock_version
      # doesn't match channel) and should be deleted
      refute Repo.get(ChannelSnapshot, old_snapshot.id)

      # Current snapshot still has a request and matches lock_version
      assert Repo.get(ChannelSnapshot, current_snapshot.id)
    end

    test "preserves snapshots still referenced by non-expired requests" do
      user = insert(:user)
      project = insert(:project)
      channel = insert(:channel, project: project)

      {:ok, old_snapshot} =
        Channels.get_or_create_current_snapshot(channel)

      {:ok, _updated_channel} =
        Channels.update_channel(channel, %{name: "updated"}, actor: user)

      # Recent request still references the old snapshot
      insert(:channel_request,
        channel: channel,
        channel_snapshot: old_snapshot,
        started_at: Lightning.current_time() |> Timex.shift(days: -6)
      )

      assert :ok = Channels.delete_expired_requests(project.id, 7)

      # Old snapshot is NOT deleted because a non-expired request
      # still references it
      assert Repo.get(ChannelSnapshot, old_snapshot.id)
    end

    test "returns :ok with no expired requests" do
      project = insert(:project)
      _channel = insert(:channel, project: project)

      assert :ok = Channels.delete_expired_requests(project.id, 7)
    end
  end

  describe "delete_channel_requests_for_project/1" do
    test "deletes all channel requests for a project" do
      project = insert(:project)
      channel = insert(:channel, project: project)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot
        )

      event =
        insert(:channel_event,
          channel_request: request,
          type: :sink_response
        )

      assert :ok =
               Channels.delete_channel_requests_for_project(%Project{
                 id: project.id
               })

      refute Repo.get(ChannelRequest, request.id)
      refute Repo.get(ChannelEvent, event.id)
    end
  end

  describe "destination auth method contract" do
    setup do
      %{user: insert(:user)}
    end

    test "cast_assoc(:destination_auth_method) auto-sets role to :destination",
         %{user: user} do
      project = insert(:project)
      pc = insert(:project_credential, project: project)

      # No "role" key in the params — the with: function should set it
      attrs = %{
        name: "auto-role",
        destination_url: "https://example.com",
        project_id: project.id,
        destination_auth_method: %{project_credential_id: pc.id}
      }

      {:ok, channel} = Channels.create_channel(attrs, actor: user)

      channel = Repo.preload(channel, :destination_auth_method)
      assert channel.destination_auth_method.role == :destination
    end

    test "cast_assoc(:client_auth_methods) auto-sets role to :client", %{
      user: user
    } do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)

      # No "role" key in the params — the with: function should set it
      attrs = %{
        name: "auto-role-client",
        destination_url: "https://example.com",
        project_id: project.id,
        client_auth_methods: [%{webhook_auth_method_id: wam.id}]
      }

      {:ok, channel} = Channels.create_channel(attrs, actor: user)

      channel = Repo.preload(channel, :client_auth_methods)
      assert length(channel.client_auth_methods) == 1
      assert hd(channel.client_auth_methods).role == :client
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

    # TODO: Remove the sink_url refutation once the rename is fully landed —
    # at that point the old field name won't exist anywhere and this negative
    # assertion adds no value.
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
        Repo.all(
          from a in Audit,
            where:
              a.item_id == ^channel.id and a.item_type == "channel" and
                a.event == "created"
        )

      assert Map.has_key?(audit.changes.after, "destination_url")
      refute Map.has_key?(audit.changes.after, "sink_url")
    end

    test "create with both client and destination auth methods", %{user: user} do
      project = insert(:project)
      wam = insert(:webhook_auth_method, project: project)
      pc = insert(:project_credential, project: project)

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
  end

  describe "delete_channel/2 with requests" do
    test "removes requests before deleting channel" do
      user = insert(:user)
      channel = insert(:channel)
      {:ok, snapshot} = Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot
        )

      event =
        insert(:channel_event,
          channel_request: request,
          type: :sink_response
        )

      assert {:ok, %Channel{}} =
               Channels.delete_channel(channel, actor: user)

      refute Repo.get(Channel, channel.id)
      refute Repo.get(ChannelRequest, request.id)
      refute Repo.get(ChannelEvent, event.id)
      refute Repo.get(ChannelSnapshot, snapshot.id)
    end
  end
end
