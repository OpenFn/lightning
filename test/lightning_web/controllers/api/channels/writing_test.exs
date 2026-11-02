defmodule LightningWeb.API.Channels.WritingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  alias Lightning.Channels.Audit
  alias Lightning.Channels.Channel
  alias Lightning.Repo

  setup %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :editor}])
    %{conn: with_pat(conn, user), user: user, project: project}
  end

  defp put_channel(conn, project, id, body),
    do: send_json(conn, :put, "/api/projects/#{project.id}/channels/#{id}", body)

  defp audits(id) do
    Repo.all(
      from a in Audit.base_query(),
        where: a.item_id == ^id,
        order_by: [a.inserted_at, a.event]
    )
  end

  defp stored(id) do
    Channel
    |> Repo.get!(id)
    |> Repo.preload([
      :client_auth_methods,
      destination_auth_method: :project_credential
    ])
  end

  defp client_ids(channel),
    do:
      channel.client_auth_methods
      |> Enum.map(& &1.webhook_auth_method_id)
      |> Enum.sort()

  defp destination(channel),
    do:
      channel.destination_auth_method &&
        channel.destination_auth_method.project_credential.credential_id

  defp with_auth(project) do
    channel = insert(:channel, project: project, name: "proxy")
    kept = insert(:webhook_auth_method, project: project)
    dropped = insert(:webhook_auth_method, project: project)
    project_credential = insert(:project_credential, project: project)

    for auth_method <- [kept, dropped],
        do:
          insert(:channel_auth_method,
            channel: channel,
            webhook_auth_method: auth_method
          )

    insert(:channel_auth_method,
      channel: channel,
      role: :destination,
      webhook_auth_method: nil,
      project_credential: project_credential
    )

    %{
      channel: channel,
      kept: kept,
      dropped: dropped,
      project_credential: project_credential
    }
  end

  describe "creating" do
    test "a session token creates the channel under the path's id with its auth methods",
         %{user: user, project: project} do
      id = Ecto.UUID.generate()
      auth_method = insert(:webhook_auth_method, project: project)
      project_credential = insert(:project_credential, project: project)

      conn =
        build_conn()
        |> session_conn(user)
        |> put_channel(project, id, %{
          "name" => "dhis2-proxy",
          "destination_url" => "https://dhis2.example.org/api",
          "enabled" => false,
          "client_auth_method_ids" => [auth_method.id],
          "destination_credential_id" => project_credential.credential_id
        })

      channel = stored(id)
      base = LightningWeb.Endpoint.url()

      assert json_response(conn, 201) == %{
               "data" => %{
                 "type" => "channels",
                 "id" => id,
                 "attributes" => %{
                   "name" => "dhis2-proxy",
                   "destination_url" => "https://dhis2.example.org/api",
                   "enabled" => false,
                   "lock_version" => channel.lock_version,
                   "url" => "#{base}/channels/#{id}",
                   "client_auth_method_ids" => [auth_method.id],
                   "destination_credential_id" =>
                     project_credential.credential_id,
                   "request_count" => 0,
                   "last_activity" => nil,
                   "inserted_at" => DateTime.to_iso8601(channel.inserted_at),
                   "updated_at" => DateTime.to_iso8601(channel.updated_at)
                 },
                 "relationships" => %{},
                 "links" => %{
                   "self" => "#{base}/api/projects/#{project.id}/channels/#{id}"
                 }
               }
             }

      assert channel.project_id == project.id
      assert client_ids(channel) == [auth_method.id]
      assert destination(channel) == project_credential.credential_id

      assert Enum.map(audits(id), & &1.event) |> Enum.sort() ==
               ["auth_method_added", "auth_method_added", "created"]
    end

    test "refuses a body it cannot take with one 422, each error at its key", %{
      conn: conn,
      project: project
    } do
      elsewhere_method = insert(:webhook_auth_method)
      elsewhere_credential = insert(:project_credential)
      own = insert(:webhook_auth_method, project: project)
      blank = &entry("#/" <> &1, "required", "can't be blank")
      unseen = &entry("#/" <> &1, "not_found", "names nothing you can see")
      valid = %{"name" => "x", "destination_url" => "https://example.org"}

      for {body, entries} <- [
            {%{}, [blank.("name"), blank.("destination_url")]},
            {%{valid | "destination_url" => "ftp://example.org"},
             [
               entry(
                 "#/destination_url",
                 "format",
                 "must be either a http or https URL"
               )
             ]},
            {Map.merge(valid, %{"enabled" => "yes", "project_id" => project.id}),
             [
               entry("#/enabled", "type", "is invalid"),
               entry("#/project_id", "unknown_key", "is not accepted")
             ]},
            {Map.merge(valid, %{
               "client_auth_method_ids" => [own.id, elsewhere_method.id, "x"],
               "destination_credential_id" => elsewhere_credential.credential_id
             }),
             [
               unseen.("client_auth_method_ids/1"),
               entry("#/client_auth_method_ids/2", "type", "is not a UUID"),
               unseen.("destination_credential_id")
             ]},
            {Map.merge(valid, %{
               "client_auth_method_ids" => own.id,
               "destination_credential_id" => "x",
               "lock_version" => "1"
             }),
             [
               entry("#/client_auth_method_ids", "type", "is invalid"),
               entry("#/destination_credential_id", "type", "is not a UUID"),
               entry("#/lock_version", "type", "is invalid")
             ]}
          ] do
        id = Ecto.UUID.generate()

        conn
        |> put_channel(project, id, body)
        |> assert_problem(422, :invalid, entries)

        refute Repo.get(Channel, id)
      end
    end

    test "answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      project: project
    } do
      conn
      |> put_channel(project, Ecto.UUID.generate(), ["proxy"])
      |> assert_problem(400, :malformed, [])
    end

    test "answers 422 with a taken entry for a name another channel in the project has, creating or renaming",
         %{conn: conn, project: project} do
      insert(:channel, project: project, name: "taken")
      other = insert(:channel, project: project, name: "other")
      id = Ecto.UUID.generate()

      taken = [
        entry(
          "#/name",
          "taken",
          "A channel with this name already exists in this project"
        )
      ]

      for target <- [id, other.id] do
        conn
        |> put_channel(project, target, %{
          "name" => "taken",
          "destination_url" => "https://example.org"
        })
        |> assert_problem(422, :invalid, taken)
      end

      refute Repo.get(Channel, id)
      assert Repo.reload!(other).name == "other"
    end
  end

  describe "replacing" do
    test "replaces the fields and the full set of auth methods, bumping lock_version",
         %{conn: conn, project: project} do
      %{channel: channel, kept: kept} = with_auth(project)
      added = insert(:webhook_auth_method, project: project)

      conn =
        put_channel(conn, project, channel.id, %{
          "name" => "renamed",
          "destination_url" => "https://new.example.org",
          "client_auth_method_ids" => [kept.id, added.id],
          "destination_credential_id" => nil,
          "lock_version" => channel.lock_version
        })

      replaced = stored(channel.id)
      attributes = json_response(conn, 200)["data"]["attributes"]

      assert Map.take(attributes, [
               "name",
               "lock_version",
               "client_auth_method_ids",
               "destination_credential_id"
             ]) == %{
               "name" => "renamed",
               "lock_version" => channel.lock_version + 1,
               "client_auth_method_ids" => Enum.sort([kept.id, added.id]),
               "destination_credential_id" => nil
             }

      assert replaced.lock_version == channel.lock_version + 1
      assert client_ids(replaced) == Enum.sort([kept.id, added.id])
      assert destination(replaced) == nil

      assert Enum.map(audits(channel.id), & &1.event) |> Enum.sort() ==
               [
                 "auth_method_added",
                 "auth_method_removed",
                 "auth_method_removed",
                 "updated"
               ]
    end

    test "keeps the auth methods and enabled a replace leaves out", %{
      conn: conn,
      project: project
    } do
      %{channel: channel, kept: kept, dropped: dropped} = with_auth(project)
      Repo.update!(Ecto.Changeset.change(channel, enabled: false))

      conn =
        put_channel(conn, project, channel.id, %{
          "name" => "renamed",
          "destination_url" => channel.destination_url
        })

      assert json_response(conn, 200)
      replaced = stored(channel.id)

      assert replaced.name == "renamed"
      refute replaced.enabled
      assert client_ids(replaced) == Enum.sort([kept.id, dropped.id])
      assert destination(replaced)
    end

    test "re-sending what is stored answers 200, keeps lock_version and records nothing",
         %{conn: conn, project: project} do
      %{channel: channel, kept: kept, dropped: dropped, project_credential: pc} =
        with_auth(project)

      conn =
        put_channel(conn, project, channel.id, %{
          "name" => channel.name,
          "destination_url" => channel.destination_url,
          "enabled" => true,
          "client_auth_method_ids" => [dropped.id, kept.id],
          "destination_credential_id" => pc.credential_id,
          "lock_version" => channel.lock_version
        })

      assert json_response(conn, 200)["data"]["attributes"]["lock_version"] ==
               channel.lock_version

      assert Repo.reload!(channel).lock_version == channel.lock_version
      assert audits(channel.id) == []
    end

    test "answers 409 concurrent_edit for a lock_version other than the channel's",
         %{conn: conn, project: project} do
      channel = insert(:channel, project: project, name: "proxy")

      for name <- ["proxy", "renamed"] do
        conn
        |> put_channel(project, channel.id, %{
          "name" => name,
          "destination_url" => channel.destination_url,
          "lock_version" => channel.lock_version + 7
        })
        |> assert_problem(409, :concurrent_edit, [])
      end

      assert Repo.reload!(channel).name == "proxy"
      assert audits(channel.id) == []
    end
  end
end
