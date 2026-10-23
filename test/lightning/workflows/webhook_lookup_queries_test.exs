defmodule Lightning.Workflows.WebhookLookupQueriesTest do
  @moduledoc """
  Webhook ingest is the hottest path in the app, so the number of queries a
  lookup costs is pinned rather than assumed.

  `async: false` because the telemetry handler sees every process's queries.
  """
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Lightning.QueryCountHelpers

  alias Lightning.Workflows
  alias Lightning.Workflows.Trigger

  defp webhook_trigger(attrs \\ []) do
    project = insert(:project)
    workflow = insert(:workflow, project: project)

    trigger =
      insert(
        :trigger,
        Keyword.merge([workflow: workflow, type: :webhook, enabled: true], attrs)
      )

    {project, trigger}
  end

  test "the namespaced URL is one query" do
    {project, _trigger} = webhook_trigger(custom_path: "facility-001")

    assert {_, 1} =
             count_queries(
               fn ->
                 Workflows.get_webhook_trigger([project.id, "facility-001"])
               end,
               "triggers"
             )
  end

  test "the generated URL is one query" do
    {_project, trigger} = webhook_trigger()

    assert {_, 1} =
             count_queries(
               fn -> Workflows.get_webhook_trigger([trigger.id]) end,
               "triggers"
             )
  end

  test "the generated URL with a trailing segment costs one more" do
    # The long-standing /i/<id>/Patient habit pays for the namespaced form
    # being tried first, which is the shape this feature creates.
    {_project, trigger} = webhook_trigger()

    assert {_, 2} =
             count_queries(
               fn -> Workflows.get_webhook_trigger([trigger.id, "Patient"]) end,
               "triggers"
             )
  end

  test "a miss costs no more than three" do
    {_, queries} =
      count_queries(
        fn -> Workflows.get_webhook_trigger([Ecto.UUID.generate(), "nope"]) end,
        "triggers"
      )

    assert queries <= 3

    assert Trigger
  end
end
