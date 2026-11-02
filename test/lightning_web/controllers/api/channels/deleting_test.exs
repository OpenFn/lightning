defmodule LightningWeb.API.Channels.DeletingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import Lightning.RaceHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  alias Lightning.Channels.Audit
  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelRequest
  alias Lightning.Repo

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :editor}])
    channel = insert(:channel, project: project, name: "proxy")
    snapshot = insert(:channel_snapshot, channel: channel)
    %{user: user, project: project, channel: channel, snapshot: snapshot}
  end

  defp audit_events(id) do
    Repo.all(
      from a in Audit.base_query(), where: a.item_id == ^id, select: a.event
    )
  end

  describe "deleting" do
    test "a session token deletes the channel and every request recorded for it",
         %{user: user, project: project, channel: channel, snapshot: snapshot} do
      request =
        insert(:channel_request, channel: channel, channel_snapshot: snapshot)

      conn =
        build_conn()
        |> session_conn(user)
        |> delete(~p"/api/projects/#{project.id}/channels/#{channel.id}")

      assert response(conn, 204) == ""
      refute Repo.get(Channel, channel.id)
      refute Repo.get(ChannelRequest, request.id)
      assert audit_events(channel.id) == ["deleted"]
    end
  end

  describe "stale writes" do
    test "a request recorded while the channel deletes answers 409 concurrent_edit, keeping the channel",
         %{conn: conn, user: user, project: project, channel: channel} = ctx do
      after_first_query("channel_requests", channel.id, fn _id ->
        insert(:channel_request,
          channel: channel,
          channel_snapshot: ctx.snapshot
        )
      end)

      conn
      |> with_pat(user)
      |> delete(~p"/api/projects/#{project.id}/channels/#{channel.id}")
      |> assert_problem(409, :concurrent_edit, [])

      assert Repo.get(Channel, channel.id)
      assert audit_events(channel.id) == []
    end

    test "a channel another request deletes mid-delete answers 409 concurrent_edit",
         %{conn: conn, user: user, project: project, channel: channel} do
      after_first_query("channels", channel.id, fn id ->
        Repo.query!("DELETE FROM channels WHERE id = $1", [id])
      end)

      conn
      |> with_pat(user)
      |> delete(~p"/api/projects/#{project.id}/channels/#{channel.id}")
      |> assert_problem(409, :concurrent_edit, [])

      assert audit_events(channel.id) == []
    end

    test "a channel another request deletes mid-replace answers 409 concurrent_edit",
         %{conn: conn, user: user, project: project, channel: channel} do
      after_first_query("channels", channel.id, fn id ->
        Repo.query!("DELETE FROM channels WHERE id = $1", [id])
      end)

      conn
      |> with_pat(user)
      |> send_json(:put, "/api/projects/#{project.id}/channels/#{channel.id}", %{
        "name" => "renamed",
        "destination_url" => channel.destination_url
      })
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.get(Channel, channel.id)
    end

    test "a channel another request changes mid-replace answers 409 concurrent_edit, keeping the other change",
         %{conn: conn, user: user, project: project, channel: channel} do
      after_first_query("channels", channel.id, fn id ->
        Repo.query!(
          "UPDATE channels SET name = 'theirs', lock_version = lock_version + 1 WHERE id = $1",
          [id]
        )
      end)

      conn
      |> with_pat(user)
      |> send_json(:put, "/api/projects/#{project.id}/channels/#{channel.id}", %{
        "name" => "mine",
        "destination_url" => channel.destination_url
      })
      |> assert_problem(409, :concurrent_edit, [])

      assert Repo.reload!(channel).name == "theirs"
    end
  end
end
