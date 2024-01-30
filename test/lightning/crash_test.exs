# This will be handled in https://github.com/OpenFn/Lightning/issues/1300
# defmodule Lightning.CrashTest do
#   use Lightning.DataCase, async: false
#   # use Oban.Testing, repo: Lightning.Repo

#   alias Lightning.Pipeline
#   alias Lightning.ObanManager
#   alias Lightning.RunStep
#   alias Lightning.Run
#   alias Lightning.Invocation.Step
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

#       step =
#         step_fixture(
#           job_id: job.id,
#           input_dataclip_id:
#             dataclip_fixture(
#               body: %{"foo" => "bar"},
#               project_id: project.id,
#               type: :http_request
#             ).id
#         )

#       dataclip = dataclip_fixture()

#       {:ok, run_step} =
#         RunStep.new()
#         |> Ecto.Changeset.put_assoc(
#           :run,
#           Run.changeset(%Run{}, %{
#             work_order_id: work_order_fixture(workflow_id: job.workflow_id).id,
#             reason_id:
#               reason_fixture(
#                 trigger_id: trigger.id,
#                 dataclip_id: dataclip.id
#               ).id
#           })
#         )
#         |> Ecto.Changeset.put_assoc(
#           :step,
#           Step.changeset(%Step{}, %{
#             project_id: job.workflow.project_id,
#             job_id: job.id,
#             input_dataclip_id: dataclip.id
#           })
#         )
#         |> Repo.insert()

#       %{step: step, run_step: run_step}
#     end

#     @tag skip: "Deprecated. To be deleted"
#     test "timeout jobs generate results with :killed status", %{step: step} do
#       result = Pipeline.Runner.start(step)

#       assert result.exit_reason == :killed

#       assert File.read!(result.final_state_path) == ""

#       step =
#         Repo.reload!(step)
#         |> Repo.preload(:output_dataclip)

#       assert step.output_dataclip == nil

#       refute is_nil(step.started_at)
#       refute is_nil(step.finished_at)
#       assert step.exit_code == nil
#     end

#     @tag skip: "Deprecated. To be deleted"
#     test "handle_event/4 marks a job as finished for :killed jobs", %{
#       run_step: run_step
#     } do
#       refute run_step.step.finished_at

#       with_log(fn ->
#         ObanManager.handle_event(
#           [:oban, :job, :exception],
#           %{duration: 5_096_921_850, queue_time: 106_015_000},
#           %{
#             job: %{
#               args: %{"run_step_id" => run_step.id},
#               worker: "Lightning.Pipeline"
#             },
#             error: %CaseClauseError{term: :killed},
#             stacktrace: []
#           },
#           nil
#         )
#       end)

#       step = Repo.get!(Step, run_step.step.id)

#       assert step.finished_at
#     end

#     @tag skip: "Deprecated. To be deleted"
#     test "handle_event/4 marks a job as finished for :timeout jobs", %{
#       run_step: run_step
#     } do
#       refute run_step.step.finished_at

#       with_log(fn ->
#         ObanManager.handle_event(
#           [:oban, :job, :exception],
#           %{duration: 5_096_921_850, queue_time: 106_015_000},
#           %{
#             job: %{
#               args: %{"run_step_id" => run_step.id},
#               worker: "Lightning.Pipeline"
#             },
#             error: %CaseClauseError{term: :timeout},
#             stacktrace: []
#           },
#           nil
#         )
#       end)

#       step = Repo.get!(Step, run_step.step.id)

#       assert step.finished_at
#     end
#   end
# end
