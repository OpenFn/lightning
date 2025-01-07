defmodule Lightning.AiAssistantTest do
  use Lightning.DataCase, async: true
  import Mox

  alias Lightning.AiAssistant

  setup :verify_on_exit!

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:simple_workflow, project: project)
    [user: user, project: project, workflow: workflow]
  end

  describe "available?/1" do
    test "is not available for users without openfn.org email" do
      user = build(:user, email: "test@openFn.org")
      assert AiAssistant.available?(user)

      user = build(:user, email: "test@example.net")
      refute AiAssistant.available?(user)
    end
  end

  describe "endpoint_available?" do
    test "availability" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 200}}
      end)

      assert Lightning.AiAssistant.endpoint_available?() == true

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 404}}
      end)

      assert Lightning.AiAssistant.endpoint_available?() == false

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 301}}
      end)

      assert Lightning.AiAssistant.endpoint_available?() == false

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:error, "socket closed"}
      end)

      assert Lightning.AiAssistant.endpoint_available?() == false
    end
  end

  describe "query/2" do
    test "queries and saves the response", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [%{role: :user, content: "what?", user: user}]
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      reply =
        """
        {
          "response": "Based on the provided guide and the API documentation for the OpenFn @openfn/language-common@1.14.0 adaptor, you can create jobs using the functions provided by the API to interact with different data sources and perform various operations.\\n\\nTo create a job using the HTTP adaptor, you can use functions like `get`, `post`, `put`, `patch`, `head`, and `options` to make HTTP requests. Here's an example job code using the HTTP adaptor:\\n\\n```javascript\\nconst { get, post, each, dataValue } = require('@openfn/language-common');\\n\\nexecute(\\n  get('/patients'),\\n  each('$.data.patients[*]', (item, index) => {\\n    item.id = `item-${index}`;\\n  }),\\n  post('/patients', dataValue('patients'))\\n);\\n```\\n\\nIn this example, the job first fetches patient data using a GET request, then iterates over each patient to modify their ID, and finally posts the modified patient data back.\\n\\nYou can similarly create jobs using the Salesforce adaptor or the ODK adaptor by utilizing functions like `upsert`, `create`, `fields`, `field`, etc., as shown in the provided examples.\\n\\nFeel free to ask if you have any specific questions or need help with",
          "history": [
            { "role": "user", "content": "what?" },
            {
              "role": "assistant",
              "content": "Based on the provided guide and the API documentation for the OpenFn @openfn/language-common@1.14.0 adaptor, you can create jobs using the functions provided by the API to interact with different data sources and perform various operations.\\n\\nTo create a job using the HTTP adaptor, you can use functions like `get`, `post`, `put`, `patch`, `head`, and `options` to make HTTP requests. Here's an example job code using the HTTP adaptor:\\n\\n```javascript\\nconst { get, post, each, dataValue } = require('@openfn/language-common');\\n\\nexecute(\\n  get('/patients'),\\n  each('$.data.patients[*]', (item, index) => {\\n    item.id = `item-${index}`;\\n  }),\\n  post('/patients', dataValue('patients'))\\n);\\n```\\n\\nIn this example, the job first fetches patient data using a GET request, then iterates over each patient to modify their ID, and finally posts the modified patient data back.\\n\\nYou can similarly create jobs using the Salesforce adaptor or the ODK adaptor by utilizing functions like `upsert`, `create`, `fields`, `field`, etc., as shown in the provided examples.\\n\\nFeel free to ask if you have any specific questions or need help with"
            }
          ]
        }
        """
        |> Jason.decode!()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post, url: url}, _opts ->
        assert url =~ "/services/job_chat"

        {:ok, %Tesla.Env{status: 200, body: reply}}
      end)

      {:ok, updated_session} = AiAssistant.query(session, "foo")

      assert Enum.count(updated_session.messages) == Enum.count(reply["history"])

      reply_message = List.last(reply["history"])
      saved_message = List.last(updated_session.messages)

      assert reply_message["content"] == saved_message.content
      assert reply_message["role"] == to_string(saved_message.role)

      assert Lightning.Repo.reload!(saved_message)
    end
  end

  describe "list_sessions_for_job/1" do
    test "lists the sessions in descending order of time updated", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      session_1 =
        insert(:chat_session,
          user: user,
          job: job_1,
          updated_at: DateTime.utc_now() |> DateTime.add(-5)
        )

      session_2 = insert(:chat_session, user: user, job: job_1)

      assert [list_session_1, list_session_2] =
               AiAssistant.list_sessions_for_job(job_1)

      assert list_session_1.id == session_2.id
      assert list_session_2.id == session_1.id

      assert is_struct(list_session_1.user),
             "user who created the session is preloaded"
    end
  end

  describe "create_session/3" do
    test "creates a new session", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      assert {:ok, session} = AiAssistant.create_session(job_1, user, "foo")

      assert session.job_id == job_1.id
      assert session.user_id == user.id
      assert session.expression == job_1.body

      assert session.adaptor ==
               Lightning.AdaptorRegistry.resolve_adaptor(job_1.adaptor)

      assert match?(
               [%{role: :user, content: "foo", user: ^user}],
               session.messages
             )
    end

    test "truncates long session titles", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      long_content =
        "This is a very long content that should be truncated because it exceeds forty characters by quite a bit"

      assert {:ok, session} =
               AiAssistant.create_session(job_1, user, long_content)

      assert session.title == "This is a very long content that should"
    end

    test "handles single-word session titles", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      single_word =
        "ThisIsOneVeryLongWordThatShouldDefinitelyBeTruncatedAtSomePoint"

      assert {:ok, session} =
               AiAssistant.create_session(job_1, user, single_word)

      assert session.title == "ThisIsOneVeryLongWordThatShouldDefinitel"
    end

    test "removes trailing punctuation from session titles", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      content_with_punctuation = "How does this work?"

      assert {:ok, session} =
               AiAssistant.create_session(job_1, user, content_with_punctuation)

      assert session.title == "How does this work"
    end

    test "preserves short content as session title", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      short_content = "Quick question"

      assert {:ok, session} =
               AiAssistant.create_session(job_1, user, short_content)

      assert session.title == "Quick question"
    end
  end

  describe "save_message/2" do
    test "calls limiter to increment ai queries when role is assistant" do
      user = insert(:user)

      %{id: job_id} = job = insert(:job, workflow: build(:workflow))

      session = insert(:chat_session, job: job, user: user)

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :increment_ai_usage,
        1,
        fn %{job_id: ^job_id}, _usage -> Ecto.Multi.new() end
      )

      content1 = """
      I am an assistant and I am here to help you with your questions.
      """

      AiAssistant.save_message(session, %{
        role: :assistant,
        content: content1,
        user: user
      })
    end

    test "does not call limiter to increment ai queries when role is user" do
      user = insert(:user)

      %{id: job_id} = job = insert(:job, workflow: build(:workflow))
      session = insert(:chat_session, job: job, user: user)

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :increment_ai_usage,
        0,
        fn %{job_id: ^job_id}, _usage -> Ecto.Multi.new() end
      )

      AiAssistant.save_message(session, %{
        role: :user,
        content: "What if I want to deduplicate the headers?",
        user: user
      })
    end
  end

  describe "update_message_status/3" do
    test "successfully updates message status to success", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      message =
        insert(:chat_message,
          content: "test",
          role: :user,
          user: user,
          status: :error
        )

      session =
        insert(:chat_session, user: user, job: job_1, messages: [message])

      assert {:ok, updated_session} =
               AiAssistant.update_message_status(session, message, :success)

      updated_message = List.first(updated_session.messages)
      assert updated_message.status == :success
    end

    test "successfully updates message status to error", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      message =
        insert(:chat_message,
          content: "test",
          role: :user,
          user: user,
          status: :success
        )

      session =
        insert(:chat_session, user: user, job: job_1, messages: [message])

      assert {:ok, updated_session} =
               AiAssistant.update_message_status(session, message, :error)

      updated_message = List.first(updated_session.messages)
      assert updated_message.status == :error
    end

    test "successfully updates message status to cancelled", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      message =
        insert(:chat_message,
          content: "test",
          role: :user,
          user: user,
          status: :success
        )

      session =
        insert(:chat_session, user: user, job: job_1, messages: [message])

      assert {:ok, updated_session} =
               AiAssistant.update_message_status(session, message, :cancelled)

      # Note: Since get_session! filters out cancelled messages, we should not see it in updated_session
      assert updated_session.messages == []
    end

    test "returns error changeset when status update fails", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      message = insert(:chat_message, content: "test", role: :user, user: user)

      session =
        insert(:chat_session, user: user, job: job_1, messages: [message])

      assert {:error, changeset} =
               AiAssistant.update_message_status(
                 session,
                 message,
                 :invalid_status
               )

      assert %Ecto.Changeset{} = changeset
      assert "is invalid" in errors_on(changeset).status
    end

    test "handles non-existent session", %{
      user: user
    } do
      message = insert(:chat_message, content: "test", role: :user, user: user)
      # Session doesn't exist in DB
      session = build(:chat_session, id: Ecto.UUID.generate())

      assert_raise Ecto.NoResultsError, fn ->
        AiAssistant.update_message_status(session, message, :success)
      end
    end

    test "updates message status for session with multiple messages", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      message1 =
        insert(:chat_message,
          content: "test1",
          role: :user,
          user: user,
          status: :error
        )

      message2 =
        insert(:chat_message,
          content: "test2",
          role: :assistant,
          user: user,
          status: :error
        )

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [message1, message2]
        )

      assert {:ok, updated_session} =
               AiAssistant.update_message_status(session, message1, :success)

      [updated_message2, updated_message1] = updated_session.messages
      assert updated_message1.status == :success
      assert updated_message2.status == :error
    end
  end
end
