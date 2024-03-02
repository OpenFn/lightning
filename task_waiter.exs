{:ok, task} =
  Task.start(fn ->
    Process.sleep(1000)
    :foo
  end)
  |> IO.inspect()

Task.await_many([
  Task.async(fn ->
    Task.await(%Task{ref: task}) |> IO.inspect(label: "1")
  end),
  Task.async(fn ->
    Task.await(task) |> IO.inspect(label: "2")
  end)
])
