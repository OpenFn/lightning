defmodule Lightning.AttemptsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Attempts

  import Lightning.Factories

  describe "enqueue/1" do
    test "enqueues an attempt" do
      trigger = build(:trigger, type: :webhook)

      job =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          name: "First Job"
        )

      workflow =
        build(:workflow)
        |> with_job(job)
        |> with_trigger(trigger)
        |> with_edge({trigger, job})
        |> insert()

      dataclip = insert(:dataclip)

      reason =
        insert(:reason,
          type: trigger.type,
          trigger: trigger |> Repo.reload(),
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)

      attempt = insert(:attempt, work_order: work_order, reason: reason)

      assert {:ok, %Attempts.Queue{} = queue} = Attempts.enqueue(attempt)

      assert queue.attempt_id == attempt.id
    end
  end
end
