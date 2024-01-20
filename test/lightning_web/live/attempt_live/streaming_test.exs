defmodule LightningWeb.AttemptLive.StreamingTest do
  use Lightning.DataCase, async: true

  alias LightningWeb.AttemptLive.Streaming

  defp create_runs_dataclips(_context) do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user}])

    credential1 =
      insert(:credential,
        name: "My Credential1",
        body: %{
          secret: "55"
        },
        user: user
      )

    credential2 =
      insert(:credential,
        name: "My Credential2",
        body: %{
          pin: 123_456,
          looks_like_a_number: "789"
        },
        user: user
      )

    credential3 =
      insert(:credential,
        name: "My Credential3",
        body: %{
          foo: "bar"
        },
        user: user
      )

    project_credential1 =
      insert(:project_credential, credential: credential1, project: project)

    project_credential2 =
      insert(:project_credential, credential: credential2, project: project)

    project_credential3 =
      insert(:project_credential, credential: credential3, project: project)

    workflow = insert(:workflow, project: project)
    trigger = insert(:trigger, workflow: workflow)

    job1 =
      insert(:job, project_credential: project_credential1, workflow: workflow)

    job2 =
      insert(:job, project_credential: project_credential2, workflow: workflow)

    job3 =
      insert(:job, project_credential: project_credential3, workflow: workflow)

    output_dataclip =
      insert(:dataclip,
        project: project,
        type: :step_result,
        body: %{
          integer: 123_456,
          another_no: 789,
          third_no: 125_534,
          map: %{list: [%{"any-key" => "some-bars"}]},
          bool: true,
          foo: "bar"
        }
      )

    input_dataclip = insert(:dataclip)

    now = DateTime.utc_now()

    run1 = insert(:step, job: job1, started_at: now)

    run2 =
      insert(:step,
        exit_reason: "success",
        job: job2,
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        started_at: DateTime.add(now, 1, :microsecond)
      )

    run3 =
      insert(:step, job: job3, started_at: DateTime.add(now, 2, :microsecond))

    attempt =
      insert(:attempt,
        work_order:
          build(:workorder,
            workflow: workflow,
            dataclip: input_dataclip,
            trigger: trigger,
            state: :success
          ),
        starting_trigger: trigger,
        state: :success,
        dataclip: input_dataclip,
        runs: [run1, run2]
      )

    insert(:attempt_run, attempt: attempt, run: run1)
    insert(:attempt_run, attempt: attempt, run: run2)
    insert(:attempt_run, attempt: attempt, run: run3)

    %{attempt: attempt, output_dataclip: output_dataclip, job: job2, run2: run2}
  end

  describe "get_dataclip_lines" do
    setup :create_runs_dataclips

    test "streams scrubbed lines from step_result dataclip", %{run2: selected_run} do
      dataclip_lines =
        Streaming.get_dataclip_lines(selected_run, :output_dataclip)
        |> elem(1)
        |> Enum.to_list()

      # foo: "bar" is not scrubbed because it is from a following job executed on run3
      expected_lines = [
        ~S("integer":***),
        ~S("another_no":***),
        ~S("third_no":12***34),
        ~S("map":{"list":[{"any-key":"some-***s"}]}),
        ~S("bool":true),
        ~S("foo":"bar")
      ]

      Enum.each(dataclip_lines, fn %{line: line} ->
        Enum.any?(expected_lines, fn expected_line ->
          String.contains?(line, expected_line)
        end)
      end)
    end
  end
end
