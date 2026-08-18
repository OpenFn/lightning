defmodule Lightning.AiAssistant.StuckMessageReaperTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.MessageProcessor
  alias Lightning.AiAssistant.StuckMessageReaper
  alias Lightning.Repo

  setup do
    user = insert(:user)
    project = insert(:project)
    workflow = insert(:simple_workflow, project: project)

    session =
      insert(:chat_session,
        user: user,
        project: project,
        workflow: workflow,
        session_type: "workflow_template"
      )

    %{session: session, user: user}
  end

  defp processing_message(session, user, started_at) do
    insert(:chat_message,
      chat_session: session,
      user: user,
      role: :user,
      content: "hello",
      status: :processing,
      processing_started_at: started_at
    )
  end

  defp long_ago do
    DateTime.utc_now()
    |> DateTime.add(
      -(MessageProcessor.timeout(nil) + :timer.minutes(10)),
      :millisecond
    )
  end

  test "clears a message abandoned in processing", %{
    session: session,
    user: user
  } do
    message = processing_message(session, user, long_ago())

    assert :ok = StuckMessageReaper.perform(%Oban.Job{})

    reloaded = Repo.get!(ChatMessage, message.id)
    assert reloaded.status == :error
    assert reloaded.failure_category == :abandoned
    assert reloaded.processing_completed_at != nil
  end

  test "tells the session, so a watching panel unblocks", %{
    session: session,
    user: user
  } do
    processing_message(session, user, long_ago())
    Lightning.subscribe("ai_session:#{session.id}")

    assert :ok = StuckMessageReaper.perform(%Oban.Job{})

    assert_receive {:ai_assistant, :message_status_changed,
                    %{status: {:error, _session}}}
  end

  test "leaves a message whose job is still running", %{
    session: session,
    user: user
  } do
    message = processing_message(session, user, long_ago())

    # Old enough to look abandoned, but Oban still has work for it - the job
    # is simply taking longer than the reaper's grace period.
    Repo.insert!(%Oban.Job{
      worker: "Lightning.AiAssistant.MessageProcessor",
      queue: "ai_assistant",
      state: "executing",
      attempted_at: DateTime.utc_now(),
      args: %{"message_id" => message.id}
    })

    assert :ok = StuckMessageReaper.perform(%Oban.Job{})

    assert Repo.get!(ChatMessage, message.id).status == :processing
  end

  test "reaps a message whose job row was orphaned mid-run", %{
    session: session,
    user: user
  } do
    message = processing_message(session, user, long_ago())

    # A node that dies mid-job leaves the row executing, and nothing moves it
    # out: Cron is the only plugin configured. Taking this at face value would
    # shield the message from every future sweep, which is the case the reaper
    # is for.
    Repo.insert!(%Oban.Job{
      worker: "Lightning.AiAssistant.MessageProcessor",
      queue: "ai_assistant",
      state: "executing",
      attempted_at: long_ago(),
      args: %{"message_id" => message.id}
    })

    assert :ok = StuckMessageReaper.perform(%Oban.Job{})

    reaped = Repo.get!(ChatMessage, message.id)
    assert reaped.status == :error
    assert reaped.failure_category == :abandoned
  end

  test "leaves a message that started recently", %{
    session: session,
    user: user
  } do
    message = processing_message(session, user, DateTime.utc_now())

    assert :ok = StuckMessageReaper.perform(%Oban.Job{})

    assert Repo.get!(ChatMessage, message.id).status == :processing
  end

  test "does not overwrite a message that finished in the meantime", %{
    session: session,
    user: user
  } do
    message = processing_message(session, user, long_ago())

    # Stands in for the job completing between the reaper's select and its
    # write. The guarded update must find nothing to change.
    {:ok, _} =
      message
      |> Ecto.Changeset.change(%{status: :success})
      |> Repo.update()

    assert :ok = StuckMessageReaper.perform(%Oban.Job{})

    reloaded = Repo.get!(ChatMessage, message.id)
    assert reloaded.status == :success
    assert reloaded.failure_category == nil
  end
end
