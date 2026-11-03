defmodule LightningWeb.API.AiSessionHelpers do
  @moduledoc """
  A project member calling the AI assistant routes with a session token, and
  the sessions they read.
  """
  import Lightning.Factories
  import LightningWeb.API.SessionHelpers

  @doc """
  A member of a new project with a saved workflow, signed in with a session
  token. Messages are queued, not answered, so no test reaches the assistant.
  `role` is the member's role.
  """
  def ai_member(role \\ :editor) do
    Process.put(:oban_testing, :manual)

    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: role}])
    workflow = insert(:simple_workflow, project: project)

    %{
      conn: session_conn(Phoenix.ConnTest.build_conn(), user),
      user: user,
      project: project,
      workflow: workflow,
      job: hd(workflow.jobs)
    }
  end

  @doc "A workflow session in `project`, with `messages` inserted in it and loaded."
  def workflow_session(project, workflow, user, messages \\ []) do
    session =
      insert(:chat_session,
        session_type: "workflow_template",
        project: project,
        workflow: workflow,
        user: user
      )

    for attrs <- messages,
        do: insert(:chat_message, Map.merge(%{chat_session: session}, attrs))

    Lightning.Repo.preload(session, [messages: :user], force: true)
  end

  @doc "The URL a session's `self` link holds."
  def ai_session_url(id),
    do: "#{LightningWeb.Endpoint.url()}/api/ai_sessions/#{id}"

  @doc "A run of `job` in `workflow`, and the step it ran: `{run, step}`."
  def run_with_step(workflow, job) do
    work_order =
      insert(:workorder, workflow: workflow, dataclip: insert(:dataclip))

    run =
      insert(:run,
        work_order: work_order,
        dataclip: work_order.dataclip,
        starting_job: job
      )

    step = insert(:step, job: job, runs: [run])
    {run, step}
  end
end
