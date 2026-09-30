defmodule LightningWeb.ObservabilityTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Observability

  setup do
    on_exit(fn -> Sentry.Context.clear_all() end)
    :ok
  end

  test "user_id becomes the Sentry user, the rest become tags" do
    :ok =
      Observability.put_scope(
        user_id: "u-1",
        project_id: "p-1",
        workflow_id: nil
      )

    context = Sentry.Context.get_all()

    assert context.user == %{id: "u-1"}
    assert context.tags == %{project_id: "p-1"}

    metadata = Logger.metadata()

    assert metadata[:user_id] == "u-1"
    assert metadata[:project_id] == "p-1"
    refute Keyword.has_key?(metadata, :workflow_id)
  end
end
