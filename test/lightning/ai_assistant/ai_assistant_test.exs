defmodule Lightning.AiAssistantTest do
  use Lightning.DataCase, async: true
  import Mox

  alias Lightning.Accounts
  alias Lightning.AiAssistant

  setup :verify_on_exit!

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:simple_workflow, project: project)
    [user: user, project: project, workflow: workflow]
  end

  describe "endpoint_available?" do
    test "availability" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
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
          :timeout -> 5_000
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

    test "handles timeout errors", %{user: user, workflow: %{jobs: [job_1 | _]}} do
      session = insert(:chat_session, user: user, job: job_1)

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :timeout}
      end)

      assert {:error, "Request timed out. Please try again."} =
               AiAssistant.query(session, "test query")
    end

    test "handles connection refused errors", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      session = insert(:chat_session, user: user, job: job_1)

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :econnrefused}
      end)

      assert {:error, "Unable to reach the AI server. Please try again later."} =
               AiAssistant.query(session, "test query")
    end

    test "handles HTTP error responses", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      session = insert(:chat_session, user: user, job: job_1)

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:ok,
         %Tesla.Env{status: 500, body: %{"message" => "Internal server error"}}}
      end)

      assert {:error, "Internal server error"} =
               AiAssistant.query(session, "test query")
    end

    test "handles unexpected errors", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      session = insert(:chat_session, user: user, job: job_1)

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, %{some: "unexpected error"}}
      end)

      assert {:error, "Oops! Something went wrong. Please try again."} =
               AiAssistant.query(session, "test query")
    end

    test "updates pending user message status on success", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      pending_message =
        insert(:chat_message,
          content: "test query",
          role: :user,
          user: user,
          status: :pending
        )

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [pending_message]
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      reply = %{
        "history" => [
          %{"role" => "user", "content" => "test query"},
          %{"role" => "assistant", "content" => "AI response"}
        ]
      }

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:ok, %Tesla.Env{status: 200, body: reply}}
      end)

      {:ok, updated_session} = AiAssistant.query(session, "test query")

      # Find the pending message in the updated session
      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.status == :success
    end

    test "updates pending user message status on error", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      pending_message =
        insert(:chat_message,
          content: "test query",
          role: :user,
          user: user,
          status: :pending
        )

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          messages: [pending_message]
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :timeout}
      end)

      {:error, _} = AiAssistant.query(session, "test query")

      updated_session = AiAssistant.get_session!(session.id)
      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.status == :error
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

    test "generates a UUID for new session", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      assert {:ok, session} = AiAssistant.create_session(job_1, user, "test")

      assert is_binary(session.id)
      assert {:ok, _uuid} = Ecto.UUID.cast(session.id)
    end

    test "creates initial user message with pending status", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      assert {:ok, session} =
               AiAssistant.create_session(job_1, user, "test message")

      [initial_message] = session.messages
      assert initial_message.status == :pending
      assert initial_message.role == :user
      assert initial_message.content == "test message"
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

    test "calls limiter when role is string 'assistant'" do
      user = insert(:user)
      %{id: job_id} = job = insert(:job, workflow: build(:workflow))
      session = insert(:chat_session, job: job, user: user)

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :increment_ai_usage,
        1,
        fn %{job_id: ^job_id}, _usage -> Ecto.Multi.new() end
      )

      AiAssistant.save_message(session, %{
        "role" => "assistant",
        "content" => "AI response"
      })
    end

    test "updates session meta when provided" do
      user = insert(:user)
      job = insert(:job, workflow: build(:workflow))

      session =
        insert(:chat_session,
          job: job,
          user: user,
          meta: %{"existing" => "data"}
        )

      new_meta = %{"new" => "metadata", "updated" => true}

      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{
            role: :user,
            content: "test",
            user: user
          },
          %{},
          new_meta
        )

      assert updated_session.meta == new_meta
    end

    test "preserves existing meta when meta is nil" do
      user = insert(:user)
      job = insert(:job, workflow: build(:workflow))
      existing_meta = %{"existing" => "data"}
      session = insert(:chat_session, job: job, user: user, meta: existing_meta)

      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{
            role: :user,
            content: "test",
            user: user
          },
          %{},
          nil
        )

      assert updated_session.meta == existing_meta
    end

    test "returns error when message validation fails" do
      user = insert(:user)
      job = insert(:job, workflow: build(:workflow))
      session = insert(:chat_session, job: job, user: user)

      {:error, changeset} =
        AiAssistant.save_message(session, %{
          role: :user,
          user: user
        })

      assert %Ecto.Changeset{} = changeset
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

      assert Enum.find(updated_session.messages, &(&1.status == :success))
      assert Enum.find(updated_session.messages, &(&1.status == :error))
    end
  end

  describe "put_expression_and_adaptor/3" do
    test "puts expression and adaptor in session", %{user: user} do
      session = insert(:chat_session, user: user)
      expression = "fn() => { return true; }"
      adaptor = "@openfn/language-common"

      updated_session =
        AiAssistant.put_expression_and_adaptor(session, expression, adaptor)

      assert updated_session.expression == expression

      assert updated_session.adaptor ==
               Lightning.AdaptorRegistry.resolve_adaptor(adaptor)
    end
  end

  describe "get_session!/1" do
    test "returns session with messages", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      session = insert(:chat_session, user: user, job: job)
      message = insert(:chat_message, chat_session: session, user: user)

      retrieved_session = AiAssistant.get_session!(session.id)

      assert retrieved_session.id == session.id
      assert length(retrieved_session.messages) == 1
      assert hd(retrieved_session.messages).id == message.id
    end

    test "raises when session not found" do
      assert_raise Ecto.NoResultsError, fn ->
        AiAssistant.get_session!(Ecto.UUID.generate())
      end
    end

    test "filters out cancelled messages", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      session = insert(:chat_session, user: user, job: job)

      active_message =
        insert(:chat_message,
          chat_session: session,
          user: user,
          status: :success
        )

      _cancelled_message =
        insert(:chat_message,
          chat_session: session,
          user: user,
          status: :cancelled
        )

      retrieved_session = AiAssistant.get_session!(session.id)

      assert length(retrieved_session.messages) == 1
      assert hd(retrieved_session.messages).id == active_message.id
    end

    test "orders messages by inserted_at ascending", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      session = insert(:chat_session, user: user, job: job)

      _message1 =
        insert(:chat_message,
          chat_session: session,
          user: user,
          content: "first"
        )

      _message2 =
        insert(:chat_message,
          chat_session: session,
          user: user,
          content: "second"
        )

      retrieved_session = AiAssistant.get_session!(session.id)

      [first_msg, second_msg] = retrieved_session.messages
      assert first_msg.content == "first"
      assert second_msg.content == "second"
    end
  end

  describe "enabled?/0" do
    test "returns true when endpoint and api_key are configured" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      assert AiAssistant.enabled?() == true
    end

    test "returns false when endpoint is missing" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> nil
          :ai_assistant_api_key -> "api_key"
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when api_key is missing" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> nil
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when both endpoint and api_key are missing" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> nil
          :ai_assistant_api_key -> nil
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when endpoint is not a binary" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> 123
          :ai_assistant_api_key -> "api_key"
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when api_key is not a binary" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> 123
        end
      end)

      assert AiAssistant.enabled?() == false
    end
  end

  describe "user_has_read_disclaimer?/1" do
    test "returns true when user has read disclaimer within 24 hours", %{
      user: user
    } do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()

      {:ok, user} =
        Accounts.update_user_preference(
          user,
          "ai_assistant.disclaimer_read_at",
          to_string(timestamp)
        )

      assert AiAssistant.user_has_read_disclaimer?(user) == true
    end

    test "returns false when user has not read disclaimer", %{user: user} do
      assert AiAssistant.user_has_read_disclaimer?(user) == false
    end

    test "returns false when disclaimer was read more than 24 hours ago", %{
      user: user
    } do
      old_timestamp =
        DateTime.utc_now() |> DateTime.add(-25, :hour) |> DateTime.to_unix()

      {:ok, user} =
        Accounts.update_user_preference(
          user,
          "ai_assistant.disclaimer_read_at",
          to_string(old_timestamp)
        )

      assert AiAssistant.user_has_read_disclaimer?(user) == false
    end

    test "handles integer timestamps", %{user: user} do
      timestamp = DateTime.utc_now() |> DateTime.to_unix()

      {:ok, user} =
        Accounts.update_user_preference(
          user,
          "ai_assistant.disclaimer_read_at",
          timestamp
        )

      assert AiAssistant.user_has_read_disclaimer?(user) == true
    end

    test "returns false when disclaimer was read exactly 24 hours ago", %{
      user: user
    } do
      old_timestamp =
        DateTime.utc_now() |> DateTime.add(-24, :hour) |> DateTime.to_unix()

      {:ok, user} =
        Accounts.update_user_preference(
          user,
          "ai_assistant.disclaimer_read_at",
          to_string(old_timestamp)
        )

      assert AiAssistant.user_has_read_disclaimer?(user) == false
    end
  end

  describe "mark_disclaimer_read/1" do
    test "updates user preference with current timestamp", %{user: user} do
      assert {:ok, updated_user} = AiAssistant.mark_disclaimer_read(user)

      preference =
        Accounts.get_preference(updated_user, "ai_assistant.disclaimer_read_at")

      timestamp = String.to_integer(preference)
      now = DateTime.utc_now() |> DateTime.to_unix()

      assert abs(timestamp - now) < 2
    end
  end

  describe "create_workflow_session/3" do
    test "creates a new workflow session", %{user: user, project: project} do
      content = "Create a workflow for data sync"

      assert {:ok, session} =
               AiAssistant.create_workflow_session(project, user, content)

      assert session.project_id == project.id
      assert session.user_id == user.id
      assert session.session_type == "workflow_template"
      assert length(session.messages) == 1
      assert hd(session.messages).content == content
    end

    test "generates a UUID for new workflow session", %{
      user: user,
      project: project
    } do
      assert {:ok, session} =
               AiAssistant.create_workflow_session(project, user, "test")

      assert is_binary(session.id)
      assert {:ok, _uuid} = Ecto.UUID.cast(session.id)
    end

    test "initializes meta as empty map", %{user: user, project: project} do
      assert {:ok, session} =
               AiAssistant.create_workflow_session(project, user, "test")

      assert session.meta == %{}
    end

    test "creates title from content", %{user: user, project: project} do
      content = "Create a data processing workflow for customer data"

      assert {:ok, session} =
               AiAssistant.create_workflow_session(project, user, content)

      assert session.title == "Create a data processing workflow for"
    end

    test "creates initial user message with pending status", %{
      user: user,
      project: project
    } do
      assert {:ok, session} =
               AiAssistant.create_workflow_session(project, user, "test message")

      [initial_message] = session.messages
      assert initial_message.status == :pending
      assert initial_message.role == :user
      assert initial_message.content == "test message"
    end
  end

  describe "associate_workflow/2" do
    test "associates workflow with session", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      assert {:ok, updated_session} =
               AiAssistant.associate_workflow(session, workflow)

      assert updated_session.workflow_id == workflow.id
    end
  end

  describe "query_workflow/3" do
    test "queries workflow chat service", %{user: user, project: project} do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post, url: url}, _opts ->
        assert url =~ "/services/workflow_chat"

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "response" => "Workflow created",
             "response_yaml" => "workflow: example",
             "usage" => %{}
           }
         }}
      end)

      assert {:ok, updated_session} =
               AiAssistant.query_workflow(session, "Create workflow", nil)

      assert length(updated_session.messages) == 1
    end

    test "handles errors from workflow chat service", %{
      user: user,
      project: project
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:ok,
         %Tesla.Env{
           status: 400,
           body: %{"message" => "Invalid request"}
         }}
      end)

      assert {:error, "Invalid request"} =
               AiAssistant.query_workflow(session, "Create workflow", nil)
    end

    test "handles timeout errors in workflow query", %{
      user: user,
      project: project
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :timeout}
      end)

      assert {:error, "Request timed out. Please try again."} =
               AiAssistant.query_workflow(session, "Create workflow", nil)
    end

    test "handles connection refused errors in workflow query", %{
      user: user,
      project: project
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :econnrefused}
      end)

      assert {:error, "Unable to reach the AI server. Please try again later."} =
               AiAssistant.query_workflow(session, "Create workflow", nil)
    end

    test "handles unexpected errors in workflow query", %{
      user: user,
      project: project
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, %{unexpected: "error"}}
      end)

      assert {:error, "Oops! Something went wrong. Please try again."} =
               AiAssistant.query_workflow(session, "Create workflow", nil)
    end

    test "updates pending user message status on success", %{
      user: user,
      project: project
    } do
      pending_message =
        insert(:chat_message,
          content: "Create workflow",
          role: :user,
          user: user,
          status: :pending
        )

      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          messages: [pending_message]
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "response" => "Workflow created",
             "response_yaml" => "workflow: example"
           }
         }}
      end)

      {:ok, updated_session} =
        AiAssistant.query_workflow(session, "Create workflow", nil)

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.status == :success
    end

    test "updates pending user message status on error", %{
      user: user,
      project: project
    } do
      pending_message =
        insert(:chat_message,
          content: "Create workflow",
          role: :user,
          user: user,
          status: :pending
        )

      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          messages: [pending_message]
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :timeout}
      end)

      {:error, _} = AiAssistant.query_workflow(session, "Create workflow", nil)

      updated_session = AiAssistant.get_session!(session.id)
      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.status == :error
    end

    test "passes validation errors to workflow service", %{
      user: user,
      project: project
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      validation_errors = "Invalid cron expression: '0 0 * * 8'"

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post, body: body},
                                             _opts ->
        assert Jason.decode!(body)["errors"] == validation_errors

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "response" => "Fixed workflow",
             "response_yaml" => "workflow: fixed"
           }
         }}
      end)

      {:ok, _} =
        AiAssistant.query_workflow(session, "Fix the errors", validation_errors)
    end

    test "includes latest workflow YAML in request", %{
      user: user,
      project: project
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      workflow_yaml = """
      name: Event-based Workflow
      jobs:
        Transform-data:
          name: Transform data
          adaptor: "@openfn/language-common@latest"
          body: |
            // Job code here
      triggers:
        webhook:
          type: webhook
          enabled: true
      edges:
        webhook->Transform-data:
          source_trigger: webhook
          target_job: Transform-data
          condition_type: always
          enabled: true
      """

      insert(:chat_message,
        role: :assistant,
        workflow_code: workflow_yaml,
        content: "Here's your workflow",
        chat_session: session
      )

      session_with_messages = AiAssistant.get_session!(session.id)

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post, body: body},
                                             _opts ->
        assert Jason.decode!(body) |> Map.get("existing_yaml") == workflow_yaml

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "response" => "Updated workflow",
             "response_yaml" => "workflow: updated"
           }
         }}
      end)

      {:ok, _} =
        AiAssistant.query_workflow(
          session_with_messages,
          "Update the workflow",
          nil
        )
    end
  end

  describe "list_sessions/3" do
    test "lists project workflow sessions with pagination", %{
      user: user,
      project: project
    } do
      _session1 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          title: "Session 1"
        )

      _session2 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          title: "Session 2"
        )

      result = AiAssistant.list_sessions(project, :desc, offset: 0, limit: 10)

      assert %{sessions: sessions, pagination: pagination} = result
      assert length(sessions) == 2
      assert pagination.total_count == 2
      assert pagination.has_next_page == false
    end

    test "lists job sessions with pagination", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      _session1 =
        insert(:chat_session, user: user, job: job, title: "Job Session 1")

      _session2 =
        insert(:chat_session, user: user, job: job, title: "Job Session 2")

      result = AiAssistant.list_sessions(job, :desc, offset: 0, limit: 10)

      assert %{sessions: sessions, pagination: pagination} = result
      assert length(sessions) == 2
      assert pagination.total_count == 2
    end

    test "respects limit and offset parameters", %{user: user, project: project} do
      for _i <- 1..3 do
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          title: "Session"
        )
      end

      result1 = AiAssistant.list_sessions(project, :desc, offset: 0, limit: 2)
      assert length(result1.sessions) == 2
      assert result1.pagination.has_next_page == true

      result2 = AiAssistant.list_sessions(project, :desc, offset: 2, limit: 2)
      assert length(result2.sessions) == 1
      assert result2.pagination.has_next_page == false
    end

    test "sorts sessions by updated_at", %{user: user, project: project} do
      _session1 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      session2 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      future_time =
        DateTime.utc_now()
        |> DateTime.add(1, :hour)
        |> DateTime.truncate(:second)

      {:ok, _} =
        Lightning.Repo.update(
          Ecto.Changeset.change(session2, updated_at: future_time)
        )

      result_desc =
        AiAssistant.list_sessions(project, :desc, offset: 0, limit: 10)

      [first, second] = result_desc.sessions
      assert DateTime.compare(first.updated_at, second.updated_at) in [:gt, :eq]

      result_asc = AiAssistant.list_sessions(project, :asc, offset: 0, limit: 10)
      [first, second] = result_asc.sessions
      assert DateTime.compare(first.updated_at, second.updated_at) in [:lt, :eq]
    end

    test "includes message count for sessions", %{user: user, project: project} do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      insert(:chat_message,
        chat_session: session,
        user: user,
        content: "Message 1"
      )

      insert(:chat_message,
        chat_session: session,
        user: user,
        content: "Message 2"
      )

      result = AiAssistant.list_sessions(project, :desc, offset: 0, limit: 10)

      assert length(result.sessions) == 1
      session_with_count = hd(result.sessions)
      assert session_with_count.message_count == 2
    end

    test "preloads user for sessions", %{user: user, project: project} do
      insert(:chat_session,
        user: user,
        project: project,
        session_type: "workflow_template"
      )

      result = AiAssistant.list_sessions(project, :desc, offset: 0, limit: 10)

      session = hd(result.sessions)
      assert %Lightning.Accounts.User{} = session.user
      assert session.user.id == user.id
    end
  end

  describe "has_more_sessions?/2" do
    test "returns true when more sessions exist beyond current_count", %{
      user: user,
      project: project
    } do
      for _i <- 1..3 do
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )
      end

      # has_more_sessions? logic:
      # - calls list_sessions(offset: current_count, limit: 1)
      # - if session found at offset, length(sessions) = 1
      # - PaginationMeta.new(current_count + 1, 1, total_count)
      # - has_next_page = (current_count + 1) < total_count

      # current_count = 0: (0 + 1) < 3 = true
      assert AiAssistant.has_more_sessions?(project, 0) == true

      # current_count = 1: (1 + 1) < 3 = true
      assert AiAssistant.has_more_sessions?(project, 1) == true

      # current_count = 2: (2 + 1) < 3 = false
      assert AiAssistant.has_more_sessions?(project, 2) == false

      # current_count = 3: no session at offset 3, length(sessions) = 0
      # PaginationMeta.new(3 + 0, 1, 3) => (3 < 3) = false
      assert AiAssistant.has_more_sessions?(project, 3) == false
    end

    test "returns false when no sessions exist", %{user: _user, project: project} do
      # No sessions created - total_count = 0

      # current_count = 0: no sessions at offset 0, length(sessions) = 0
      # PaginationMeta.new(0 + 0, 1, 0) => (0 < 0) = false
      assert AiAssistant.has_more_sessions?(project, 0) == false
      assert AiAssistant.has_more_sessions?(project, 1) == false
    end

    test "works with job sessions", %{user: user, workflow: %{jobs: [job | _]}} do
      # Create 2 job sessions
      for _i <- 1..2 do
        insert(:chat_session, user: user, job: job)
      end

      # total_count = 2
      # current_count = 0: (0 + 1) < 2 = true
      assert AiAssistant.has_more_sessions?(job, 0) == true

      # current_count = 1: (1 + 1) < 2 = false
      assert AiAssistant.has_more_sessions?(job, 1) == false

      # current_count = 2: no session at offset 2, (2 + 0) < 2 = false
      assert AiAssistant.has_more_sessions?(job, 2) == false
    end
  end

  describe "find_pending_user_messages/1" do
    test "returns pending user messages only", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      pending_msg =
        insert(:chat_message,
          role: :user,
          user: user,
          status: :pending,
          content: "Pending"
        )

      success_msg =
        insert(:chat_message,
          role: :user,
          user: user,
          status: :success,
          content: "Success"
        )

      assistant_pending =
        insert(:chat_message,
          role: :assistant,
          status: :pending,
          content: "AI Pending"
        )

      session =
        insert(:chat_session,
          user: user,
          job: job,
          messages: [pending_msg, success_msg, assistant_pending]
        )

      pending_messages = AiAssistant.find_pending_user_messages(session)

      assert length(pending_messages) == 1
      assert hd(pending_messages).content == "Pending"
    end

    test "returns empty list when no pending user messages", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      success_msg =
        insert(:chat_message, role: :user, user: user, status: :success)

      assistant_msg = insert(:chat_message, role: :assistant, status: :pending)

      session =
        insert(:chat_session,
          user: user,
          job: job,
          messages: [success_msg, assistant_msg]
        )

      pending_messages = AiAssistant.find_pending_user_messages(session)
      assert pending_messages == []
    end
  end

  describe "title_max_length/0" do
    test "returns the configured maximum title length" do
      assert AiAssistant.title_max_length() == 40
    end
  end
end
