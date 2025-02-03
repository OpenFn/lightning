defmodule Lightning.Invocation.LogLineTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Invocation.LogLine

  test "new/2" do
    dataclip = insert(:dataclip)

    %{triggers: [trigger]} = workflow = insert(:simple_workflow)

    work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

    run =
      insert(:run,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: dataclip
      )

    log_line =
      LogLine.new(
        run,
        %{message: "Hello, World!", timestamp: DateTime.utc_now()},
        nil
      )

    assert log_line.valid?

    log_line =
      LogLine.new(
        run,
        %{message: "", timestamp: DateTime.utc_now()},
        nil
      )

    assert log_line.valid?, "should be able to have an empty message"
  end
end
