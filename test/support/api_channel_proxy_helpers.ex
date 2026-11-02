defmodule LightningWeb.API.ChannelProxyHelpers do
  @moduledoc """
  Builders and assertions the channel proxy test files share.
  """
  import ExUnit.Assertions
  import Ecto.Query
  import Lightning.Factories

  @security_headers [
    {"content-security-policy",
     "default-src 'none'; sandbox; frame-ancestors 'none'"},
    {"x-content-type-options", "nosniff"},
    {"x-frame-options", "DENY"},
    {"referrer-policy", "no-referrer"}
  ]

  def create_client_auth_channel(
        bypass,
        auth_method_specs,
        destination_token \\ nil
      ) do
    project = insert(:project)

    channel_auth_methods =
      Enum.map(auth_method_specs, fn spec ->
        build(:channel_auth_method,
          role: :client,
          webhook_auth_method:
            build(
              :webhook_auth_method,
              [project: project] ++ Enum.to_list(spec)
            )
        )
      end)

    insert(:channel,
      project: project,
      destination_url: "http://localhost:#{bypass.port}",
      enabled: true,
      channel_auth_methods:
        channel_auth_methods ++
          destination_auth_methods(project, destination_token)
    )
  end

  def destination_auth_methods(_project, nil), do: []

  def destination_auth_methods(project, token) do
    credential =
      insert(:credential,
        schema: "@openfn/language-http",
        name: "destination-cred",
        user: insert(:user)
      )
      |> with_body(%{body: %{"access_token" => token}})

    [
      build(:channel_auth_method,
        role: :destination,
        webhook_auth_method: nil,
        project_credential:
          insert(:project_credential, project: project, credential: credential)
      )
    ]
  end

  def create_destination_auth_channel(bypass, schema, body) do
    project = insert(:project)
    user = insert(:user)

    credential =
      insert(:credential, schema: schema, name: "destination-cred", user: user)
      |> with_body(%{body: body})

    project_credential =
      insert(:project_credential,
        project: project,
        credential: credential
      )

    insert(:channel,
      project: project,
      destination_url: "http://localhost:#{bypass.port}",
      enabled: true,
      channel_auth_methods: [
        build(:channel_auth_method,
          role: :destination,
          webhook_auth_method: nil,
          project_credential: project_credential
        )
      ]
    )
  end

  # A blank name passes the channels table but not the snapshot changeset, so
  # the proxy fails to snapshot without a mock.
  def unsnapshottable!(channel) do
    Lightning.Repo.update_all(
      from(c in Lightning.Channels.Channel, where: c.id == ^channel.id),
      set: [name: ""]
    )
  end

  def assert_security_headers(resp) do
    for {header, value} <- @security_headers do
      assert Plug.Conn.get_resp_header(resp, header) == [value],
             "expected #{header}: #{value}"
    end
  end

  def send_to_endpoint(conn) do
    LightningWeb.Endpoint.call(conn, LightningWeb.Endpoint.init([]))
  end
end
