defmodule LightningWeb.ChannelProxyEgressTest do
  # async: false — these tests mutate the global `:philter` application env
  # (allowed_hosts / block_private_networks), which Philter reads live per
  # request. Running them concurrently with other tests would race.
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Plug.Test, only: [conn: 2]

  setup do
    bypass = Bypass.open()
    project = insert(:project)

    # Bypass listens on 127.0.0.1, which is inside the blocked 127.0.0.0/8
    # loopback range — exactly the collision we want to exercise.
    channel =
      insert(:channel,
        project: project,
        destination_url: "http://127.0.0.1:#{bypass.port}",
        enabled: true
      )

    {:ok, bypass: bypass, channel: channel}
  end

  # Set a :philter application env key for the duration of one test, restoring
  # whatever was there before (test.exs sets allowed_hosts: ["localhost"], and
  # block_private_networks is unset — defaulting to true).
  defp put_philter_env(key, value) do
    previous = Application.fetch_env(:philter, key)

    on_exit(fn ->
      case previous do
        {:ok, prior} -> Application.put_env(:philter, key, prior)
        :error -> Application.delete_env(:philter, key)
      end
    end)

    Application.put_env(:philter, key, value)
  end

  defp send_to_endpoint(conn) do
    LightningWeb.Endpoint.call(conn, LightningWeb.Endpoint.init([]))
  end

  describe "allowed_hosts escape hatch" do
    test "an allow-listed loopback host reaches the upstream despite the block",
         %{bypass: bypass, channel: channel} do
      # Block is on (default), but 127.0.0.1 is explicitly allow-listed, so the
      # request should bypass the block and hit Bypass — the analogue of
      # allow-listing an RFC1918 address like 10.0.0.10.
      put_philter_env(:allowed_hosts, ["127.0.0.1"])

      Bypass.expect_once(bypass, "GET", "/allowed", fn conn ->
        Plug.Conn.send_resp(conn, 200, "reached upstream")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/allowed")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "reached upstream"
    end

    test "a loopback host that is NOT allow-listed is blocked before any socket",
         %{channel: channel} do
      # Exact-hostname matching: allow-listing "localhost" does NOT cover the
      # literal 127.0.0.1, so the block still applies. We assert the egress
      # message so we know the upstream was never contacted.
      put_philter_env(:allowed_hosts, ["localhost"])

      # No Bypass expectation is set: reaching the upstream could only produce a
      # 200 or a connection error, never the egress-block message asserted below.
      resp =
        conn(:get, "/channels/#{channel.id}/blocked")
        |> send_to_endpoint()

      assert resp.status == 403
      assert resp.resp_body =~ "Request blocked by egress policy"
    end
  end

  describe "block_private_networks disabled" do
    test "a loopback host reaches the upstream when the block is turned off",
         %{bypass: bypass, channel: channel} do
      # CHANNEL_BLOCK_PRIVATE_NETWORKS=false — with allowed_hosts left at its
      # test.exs default (["localhost"]), 127.0.0.1 still reaches Bypass because
      # the private-network block is disabled entirely.
      put_philter_env(:block_private_networks, false)

      Bypass.expect_once(bypass, "GET", "/unblocked", fn conn ->
        Plug.Conn.send_resp(conn, 200, "reached upstream")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/unblocked")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "reached upstream"
    end
  end
end
