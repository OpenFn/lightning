# This will be handled in
# defmodule Lightning.CrashTest do
#   use Lightning.DataCase, async: false
#   # use Oban.Testing, repo: Lightning.Repo

#   alias Lightning.Pipeline
#   alias Lightning.ObanManager
#   alias Lightning.AttemptRun
#   alias Lightning.Attempt
#   alias Lightning.Invocation.{Run}
#   alias Lightning.Repo

#   import Lightning.JobsFixtures
#   import Lightning.InvocationFixtures
#   import Lightning.ProjectsFixtures

#   import ExUnit.CaptureLog

#   describe "Oban manager" do
#     setup do
#       prev = Application.get_env(:lightning, :max_run_duration)
#       on_exit(fn -> Application.put_env(:lightning, :max_run_duration, prev) end)

#       Application.put_env(:lightning, :max_run_duration, 1 * 1000)

#       project = project_fixture()

#       %{job: job, trigger: trigger} =
#         workflow_job_fixture(
#           body: ~s[fn(state => {
#           return new Promise((resolve, reject) => {
#             setTimeout(() => {
#               console.log('wait, and then resolve');
#               resolve(state);
#             }, 2 * 1000);
#           });
#         });],
#           project_id: project.id
#         )

#       run =
#         run_fixture(
#           job_id: job.id,
#           input_dataclip_id:
#             dataclip_fixture(
#               body: %{"foo" => "bar"},
#               project_id: project.id,
#               type: :http_request
#             ).id
#         )

#       dataclip = dataclip_fixture()

#       {:ok, attempt_run} =
#         AttemptRun.new()
#         |> Ecto.Changeset.put_assoc(
#           :attempt,
#           Attempt.changeset(%Attempt{}, %{
#             work_order_id: work_order_fixture(workflow_id: job.workflow_id).id,
#             reason_id:
#               reason_fixture(
#                 trigger_id: trigger.id,
#                 dataclip_id: dataclip.id
#               ).id
#           })
#         )
#         |> Ecto.Changeset.put_assoc(
#           :run,
#           Run.changeset(%Run{}, %{
#             project_id: job.workflow.project_id,
#             job_id: job.id,
#             input_dataclip_id: dataclip.id
#           })
#         )
#         |> Repo.insert()

#       %{run: run, attempt_run: attempt_run}
#     end

#     @tag skip: "Deprecated. To be deleted"
#     test "timeout jobs generate results with :killed status", %{run: run} do
#       result = Pipeline.Runner.start(run)

#       assert result.exit_reason == :killed
#       assert result.exit_code == nil

#       assert File.read!(result.final_state_path) == ""

#       run =
#         Repo.reload!(run)
#         |> Repo.preload(:output_dataclip)

#       assert run.output_dataclip == nil

#       refute is_nil(run.started_at)
#       refute is_nil(run.finished_at)
#       assert run.exit_code == nil
#     end

#     @tag skip: "Deprecated. To be deleted"
#     test "handle_event/4 marks a job as finished for :killed jobs", %{
#       attempt_run: attempt_run
#     } do
#       refute attempt_run.run.finished_at

#       with_log(fn ->
#         ObanManager.handle_event(
#           [:oban, :job, :exception],
#           %{duration: 5_096_921_850, queue_time: 106_015_000},
#           %{
#             job: %{
#               args: %{"attempt_run_id" => attempt_run.id},
#               worker: "Lightning.Pipeline"
#             },
#             error: %CaseClauseError{term: :killed},
#             stacktrace: []
#           },
#           nil
#         )
#       end)

#       run = Repo.get!(Run, attempt_run.run.id)

#       assert run.finished_at
#     end

#     @tag skip: "Deprecated. To be deleted"
#     test "handle_event/4 marks a job as finished for :timeout jobs", %{
#       attempt_run: attempt_run
#     } do
#       refute attempt_run.run.finished_at

#       with_log(fn ->
#         ObanManager.handle_event(
#           [:oban, :job, :exception],
#           %{duration: 5_096_921_850, queue_time: 106_015_000},
#           %{
#             job: %{
#               args: %{"attempt_run_id" => attempt_run.id},
#               worker: "Lightning.Pipeline"
#             },
#             error: %CaseClauseError{term: :timeout},
#             stacktrace: []
#           },
#           nil
#         )
#       end)

#       run = Repo.get!(Run, attempt_run.run.id)

#       assert run.finished_at
#     end
#   end
# end
