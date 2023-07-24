defmodule Lightning.FactoriesTest do
  use Lightning.DataCase, async: true
  alias Lightning.Factories

  test "build(:trigger) overrides default assoc" do
    job = %{workflow: workflow} = Factories.insert(:job)

    trigger =
      Factories.insert(:trigger, %{
        type: :cron,
        cron_expression: "* * * * *",
        workflow: job.workflow
      })

    assert trigger.workflow.id == workflow.id
  end

  test "insert/1 inserts a record" do
    trigger = Factories.insert(:trigger)
    assert trigger
  end
end
