import Lightning.Factories

dataclip = insert(:dataclip, body: %{"foo" => "bar"})
%{triggers: [trigger]} = workflow = insert(:simple_workflow)

work_order =
  insert(:workorder,
    workflow: workflow,
    trigger: trigger,
    dataclip: dataclip
  )

attempt =
  insert(:attempt,
    work_order: work_order,
    starting_trigger: trigger,
    dataclip: dataclip
  )

IO.inspect(attempt)
