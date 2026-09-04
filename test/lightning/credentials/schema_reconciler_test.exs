defmodule Lightning.Credentials.SchemaReconcilerTest do
  # async: false because:
  # 1. DataCase uses shared sandbox mode (all processes access DB without allow/3)
  # 2. isolated_adaptors stubs Config.default_instance/0 via Mimic globally
  use Lightning.DataCase, async: false

  import Eventually
  import Lightning.AdaptorTestHelpers

  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.SchemaReconciler

  setup :isolated_adaptors

  defp start_reconciler(opts) do
    name = :"reconciler_#{System.unique_integer([:positive])}"
    start_supervised!({SchemaReconciler, Keyword.put(opts, :name, name)})
  end

  test "sweeps a warm catalogue on start", %{sup: sup} do
    seed_adaptor_package("@openfn/language-postgresql", "1.0.0")
    credential = insert(:credential, schema: "postgresql")

    start_reconciler(sup: sup)

    assert_eventually(
      Repo.get!(Credential, credential.id).schema ==
        "@openfn/language-postgresql"
    )
  end

  test "sweeps again when the catalogue changes after start", %{sup: sup} do
    start_reconciler(sup: sup)

    credential = insert(:credential, schema: "postgresql")

    refute Repo.get!(Credential, credential.id).schema ==
             "@openfn/language-postgresql"

    seed_adaptor_package("@openfn/language-postgresql", "1.0.0")

    Phoenix.PubSub.broadcast!(
      Lightning.PubSub,
      AdaptorsSupervisor.source_topic(sup),
      {:changed, "@openfn/language-postgresql", :npm}
    )

    assert_eventually(
      Repo.get!(Credential, credential.id).schema ==
        "@openfn/language-postgresql",
      Lightning.Adaptors.ChannelBroadcaster.debounce_ms() * 4
    )
  end

  test "retries after the sweep raises, without crashing", %{sup: sup} do
    test_pid = self()

    pid =
      start_reconciler(
        sup: sup,
        reconcile: fn _sup ->
          send(test_pid, :attempt)
          raise "boom"
        end,
        retry_ms: 20
      )

    assert_receive :attempt
    assert_receive :attempt
    assert_receive :attempt
    assert Process.alive?(pid)
  end
end
