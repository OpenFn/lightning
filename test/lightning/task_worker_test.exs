defmodule Lightning.TaskWorkerTest do
  use ExUnit.Case, async: true

  alias Lightning.TaskWorker

  test "can limit how many tasks are executed at once" do
    task_worker = start_supervised!({Lightning.TaskWorker, [max_tasks: 2]})

    results =
      Enum.map(1..5, fn i ->
        Task.async(fn ->
          TaskWorker.start_task(task_worker, fn ->
            Process.sleep(1)
            i
          end)
        end)
      end)
      |> Task.await_many(100)

    assert results
           |> Enum.filter(fn x -> x == {:error, :too_many_processes} end)
           |> length() == 3

    assert {:ok, %{max_tasks: 2, task_count: 0, task_sup: _sup}} =
             TaskWorker.get_status(task_worker)
  end
end
