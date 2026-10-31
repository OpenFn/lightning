defmodule Lightning.Workflows.WebhookLookupQueriesTest do
  @moduledoc """
  Webhook ingest is the hottest path in the app, so the number of queries a
  lookup costs is pinned rather than assumed.

  `async: false` because the telemetry handler sees every process's queries.
  """
  use Lightning.DataCase, async: false

  import Lightning.Factories

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

  defp count_queries(fun) do
    ref = make_ref()
    parent = self()
    name = "count-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      name,
      [:lightning, :repo, :query],
      fn _event, _measures, meta, _config ->
        if meta[:source] == "triggers", do: send(parent, {ref, :query})
      end,
      nil
    )

    fun.()
    :telemetry.detach(name)

    drain(ref, 0)
  end

  defp drain(ref, acc) do
    receive do
      {^ref, :query} -> drain(ref, acc + 1)
    after
      0 -> acc
    end
  end

  test "the namespaced URL is one query" do
    {project, _trigger} = webhook_trigger(custom_path: "facility-001")

    assert count_queries(fn ->
             Workflows.get_webhook_trigger([project.id, "facility-001"])
           end) == 1
  end

  test "the generated URL is one query" do
    {_project, trigger} = webhook_trigger()

    assert count_queries(fn ->
             Workflows.get_webhook_trigger([trigger.id])
           end) == 1
  end

  test "the generated URL with a trailing segment costs one more" do
    # The long-standing /i/<id>/Patient habit pays for the namespaced form
    # being tried first, which is the shape this feature creates.
    {_project, trigger} = webhook_trigger()

    assert count_queries(fn ->
             Workflows.get_webhook_trigger([trigger.id, "Patient"])
           end) == 2
  end

  test "a miss costs no more than three" do
    assert count_queries(fn ->
             Workflows.get_webhook_trigger([Ecto.UUID.generate(), "nope"])
           end) <= 3

    assert Trigger
  end
end
