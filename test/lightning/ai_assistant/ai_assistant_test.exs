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

  @moduletag :capture_log

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

  describe "query/3" do
    test "queries and saves the response", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      job_expression = "fn(state => state);\n"
      adaptor = "@openfn/language-http@7.0.6"
      message_content = "what?"

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          expression: job_expression,
          adaptor: adaptor,
          messages: [
            %{
              role: :user,
              content: message_content,
              user: user,
              status: :pending,
              # needed to avoid flaky sorting
              inserted_at: DateTime.utc_now() |> DateTime.add(-1)
            }
          ]
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

      {:ok, updated_session} = AiAssistant.query(session, message_content)
      assert updated_session.expression == job_expression
      assert updated_session.adaptor == adaptor

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
          :timeout -> 5_000
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
          :timeout -> 5_000
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
          :timeout -> 5_000
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
          :timeout -> 5_000
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, %{some: "unexpected error"}}
      end)

      assert {:error, "Oops! Something went wrong. Please try again."} =
               AiAssistant.query(session, "test query")
    end

    test "job code is included in the context by default", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      job_expression = "fn(state => state);\n"
      adaptor = "@openfn/language-http@7.0.6"

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          expression: job_expression,
          adaptor: adaptor,
          messages: [
            %{role: :user, content: "ping", user: user, status: :pending}
          ]
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      expect(
        Lightning.Tesla.Mock,
        :call,
        fn %{method: :post, body: json_body}, _opts ->
          body = Jason.decode!(json_body)
          assert body["context"]["expression"] == job_expression
          assert body["context"]["adaptor"] == adaptor

          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "user", "content" => "Ping"},
                 %{"role" => "assistant", "content" => "Pong"}
               ]
             }
           }}
        end
      )

      {:ok, _updated_session} = AiAssistant.query(session, "Ping")
    end

    test "job code can be excluded from the context via options", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      job_expression = "fn(state => state);\n"
      adaptor = "@openfn/language-http@7.0.6"

      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          expression: job_expression,
          adaptor: adaptor,
          messages: [
            %{role: :user, content: "ping", user: user, status: :pending}
          ]
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      expect(
        Lightning.Tesla.Mock,
        :call,
        fn %{method: :post, body: json_body}, _opts ->
          body = Jason.decode!(json_body)
          refute Map.has_key?(body["context"], "expression")
          assert body["context"]["adaptor"] == adaptor

          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "user", "content" => "Ping"},
                 %{"role" => "assistant", "content" => "Pong"}
               ]
             }
           }}
        end
      )

      {:ok, _updated_session} =
        AiAssistant.query(session, "Ping", code: false)
    end

    test "logs can be excluded from the context via options", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          expression: "fn()",
          adaptor: "@openfn/language-common",
          logs: "Some log data",
          messages: []
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      expect(
        Lightning.Tesla.Mock,
        :call,
        fn %{method: :post, body: json_body}, _opts ->
          body = Jason.decode!(json_body)
          refute Map.has_key?(body["context"], "log")
          assert Map.has_key?(body["context"], "expression")

          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "assistant", "content" => "Response"}
               ]
             }
           }}
        end
      )

      {:ok, _updated_session} =
        AiAssistant.query(session, "Query", logs: false)
    end

    test "input and output options are included in context", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          expression: "fn(state => state)",
          adaptor: "@openfn/language-http",
          messages: []
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      input_data = %{"user" => "john", "age" => 30}
      output_data = %{"status" => "success", "id" => "123"}

      expect(
        Lightning.Tesla.Mock,
        :call,
        fn %{method: :post, body: json_body}, _opts ->
          body = Jason.decode!(json_body)

          # Verify input and output are in context
          assert body["context"]["input"] == input_data
          assert body["context"]["output"] == output_data

          # Verify other context is still present
          assert body["context"]["expression"] == "fn(state => state)"
          assert body["context"]["adaptor"] == "@openfn/language-http"

          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "user", "content" => "Query"},
                 %{"role" => "assistant", "content" => "Response"}
               ]
             }
           }}
        end
      )

      {:ok, _updated_session} =
        AiAssistant.query(session, "Query",
          input: input_data,
          output: output_data
        )
    end

    test "nil input and output options are not included in context", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      session =
        insert(:chat_session,
          user: user,
          job: job_1,
          expression: "fn(state => state)",
          adaptor: "@openfn/language-http",
          messages: []
        )

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      expect(
        Lightning.Tesla.Mock,
        :call,
        fn %{method: :post, body: json_body}, _opts ->
          body = Jason.decode!(json_body)

          # Verify input and output are not present when nil
          refute Map.has_key?(body["context"], "input")
          refute Map.has_key?(body["context"], "output")

          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "user", "content" => "Query"},
                 %{"role" => "assistant", "content" => "Response"}
               ]
             }
           }}
        end
      )

      {:ok, _updated_session} =
        AiAssistant.query(session, "Query", input: nil, output: nil)
    end
  end

  describe "create_session/4" do
    test "creates a new session", %{
      user: user,
      workflow: %{jobs: [job_1 | _]} = _workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} = AiAssistant.create_session(job_1, user, "foo")

        assert session.job_id == job_1.id
        assert session.user_id == user.id
        assert session.expression == job_1.body

        assert session.adaptor ==
                 Lightning.AdaptorRegistry.resolve_adaptor(job_1.adaptor)

        assert length(session.messages) == 1
        message = hd(session.messages)
        assert message.role == :user
        assert message.content == "foo"
        assert message.user.id == user.id
      end)
    end

    test "accepts optional parameters", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        meta = %{"key" => "value"}
        code = "some code"

        assert {:ok, session} =
                 AiAssistant.create_session(job_1, user, "foo",
                   meta: meta,
                   code: code
                 )

        assert session.meta == meta
        [message] = session.messages
        assert message.code == code
      end)
    end

    test "truncates long session titles", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        long_content =
          "This is a very long content that should be truncated because it exceeds forty characters by quite a bit"

        assert {:ok, session} =
                 AiAssistant.create_session(job_1, user, long_content)

        assert session.title == "This is a very long content that should"
      end)
    end

    test "handles single-word session titles", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        single_word =
          "ThisIsOneVeryLongWordThatShouldDefinitelyBeTruncatedAtSomePoint"

        assert {:ok, session} =
                 AiAssistant.create_session(job_1, user, single_word)

        assert session.title == "ThisIsOneVeryLongWordThatShouldDefinitel"
      end)
    end

    test "removes trailing punctuation from session titles", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        content_with_punctuation = "How does this work?"

        assert {:ok, session} =
                 AiAssistant.create_session(
                   job_1,
                   user,
                   content_with_punctuation
                 )

        assert session.title == "How does this work"
      end)
    end

    test "preserves short content as session title", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        short_content = "Quick question"

        assert {:ok, session} =
                 AiAssistant.create_session(job_1, user, short_content)

        assert session.title == "Quick question"
      end)
    end

    test "generates a UUID for new session", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} = AiAssistant.create_session(job_1, user, "test")

        assert is_binary(session.id)
        assert {:ok, _uuid} = Ecto.UUID.cast(session.id)
      end)
    end

    test "creates session with initial user message", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_session(job_1, user, "test message")

        assert session.job_id == job_1.id
        assert session.user_id == user.id

        [initial_message] = session.messages
        assert initial_message.role == :user
        assert initial_message.content == "test message"
        assert initial_message.user_id == user.id

        assert Repo.get!(Lightning.AiAssistant.ChatMessage, initial_message.id)
      end)
    end

    test "enqueues message for processing when creating session", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_session(job_1, user, "test message")

        [message] = session.messages

        assert message.status == :pending

        assert_enqueued(
          worker: Lightning.AiAssistant.MessageProcessor,
          args: %{"message_id" => message.id}
        )
      end)
    end

    test "enqueues message for processing", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} = AiAssistant.create_session(job_1, user, "test")

        [message] = session.messages

        assert_enqueued(
          worker: Lightning.AiAssistant.MessageProcessor,
          args: %{"message_id" => message.id}
        )
      end)
    end
  end

  describe "save_message/3" do
    test "calls limiter to increment ai queries when role is assistant" do
      Oban.Testing.with_testing_mode(:manual, fn ->
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
      end)
    end

    test "does not call limiter to increment ai queries when role is user" do
      Oban.Testing.with_testing_mode(:manual, fn ->
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
      end)
    end

    test "calls limiter when role is string 'assistant'" do
      Oban.Testing.with_testing_mode(:manual, fn ->
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
      end)
    end

    test "updates session meta when provided" do
      Oban.Testing.with_testing_mode(:manual, fn ->
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
            meta: new_meta,
            usage: %{}
          )

        # Meta should be merged with existing meta, preserving "existing" key
        assert updated_session.meta == %{
                 "existing" => "data",
                 "new" => "metadata",
                 "updated" => true
               }
      end)
    end

    test "preserves existing meta when meta is nil" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        user = insert(:user)
        job = insert(:job, workflow: build(:workflow))
        existing_meta = %{"existing" => "data"}

        session =
          insert(:chat_session, job: job, user: user, meta: existing_meta)

        {:ok, updated_session} =
          AiAssistant.save_message(
            session,
            %{
              role: :user,
              content: "test",
              user: user
            },
            meta: nil,
            usage: %{}
          )

        assert updated_session.meta == existing_meta
      end)
    end

    test "returns error when message validation fails" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        user = insert(:user)
        job = insert(:job, workflow: build(:workflow))
        session = insert(:chat_session, job: job, user: user)

        {:error, changeset} =
          AiAssistant.save_message(session, %{
            role: :user,
            user: user
          })

        assert %Ecto.Changeset{} = changeset
      end)
    end

    test "saves workflow code to message when provided" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        user = insert(:user)
        project = insert(:project)
        workflow = insert(:workflow, project: project)

        session =
          insert(:chat_session,
            project: project,
            workflow: workflow,
            user: user,
            session_type: "workflow_template"
          )

        workflow_yaml = """
        workflow:
          name: Test Workflow
          jobs:
            - id: job1
              name: Fetch Data
              adaptor: "@openfn/language-http@latest"
              body: "fn(state => state)"
        """

        {:ok, updated_session} =
          AiAssistant.save_message(
            session,
            %{
              role: :user,
              content: "Please improve this workflow",
              user: user
            },
            code: workflow_yaml
          )

        saved_message = List.last(updated_session.messages)
        assert saved_message.code == workflow_yaml
        assert saved_message.role == :user
      end)
    end

    test "enqueues user message for processing when pending", %{user: user} do
      job = insert(:job, workflow: build(:workflow))
      session = insert(:chat_session, job: job, user: user)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, updated_session} =
          AiAssistant.save_message(session, %{
            role: :user,
            content: "test",
            user: user
          })

        [new_message] =
          Enum.filter(updated_session.messages, &(&1.content == "test"))

        assert_enqueued(
          worker: Lightning.AiAssistant.MessageProcessor,
          args: %{"message_id" => new_message.id}
        )
      end)
    end

    test "does not enqueue assistant messages", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        job = insert(:job, workflow: build(:workflow))
        session = insert(:chat_session, job: job, user: user)

        {:ok, _} =
          AiAssistant.save_message(session, %{
            role: :assistant,
            content: "AI response"
          })
      end)
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

    test "raises error when trying to use invalid status", %{
      user: user,
      workflow: %{jobs: [job_1 | _]}
    } do
      message = insert(:chat_message, content: "test", role: :user, user: user)

      session =
        insert(:chat_session, user: user, job: job_1, messages: [message])

      # Test that invalid status raises FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        AiAssistant.update_message_status(session, message, :invalid_status)
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

    test "preloads project for workflow template sessions", %{
      user: user,
      project: project
    } do
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template"
        )

      retrieved_session = AiAssistant.get_session!(session.id)

      assert %Lightning.Projects.Project{} = retrieved_session.project
      assert retrieved_session.project.id == project.id
    end
  end

  describe "get_session/1" do
    test "returns {:ok, session} when found", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      session = insert(:chat_session, user: user, job: job)

      assert {:ok, retrieved_session} = AiAssistant.get_session(session.id)
      assert retrieved_session.id == session.id
    end

    test "returns {:error, :not_found} when not found" do
      assert {:error, :not_found} = AiAssistant.get_session(Ecto.UUID.generate())
    end
  end

  describe "enrich_session_with_job_context/1" do
    test "enriches session with job expression and adaptor", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      session = insert(:chat_session, user: user, job: job)

      enriched = AiAssistant.enrich_session_with_job_context(session)

      assert enriched.expression == job.body

      assert enriched.adaptor ==
               Lightning.AdaptorRegistry.resolve_adaptor(job.adaptor)
    end

    test "adds run logs when follow_run_id is in meta", %{
      user: user,
      workflow: %{jobs: [job | _]} = workflow
    } do
      # Create work_order first
      work_order = insert(:workorder, workflow: workflow)

      run =
        insert(:run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: job
        )

      # Create a step for the job
      step = insert(:step, job: job)

      insert(:run_step, run: run, step: step)

      # Important: set the run_id for log lines
      insert(:log_line,
        step: step,
        run: run,
        message: "Starting job execution",
        timestamp: ~U[2024-01-01 10:00:00Z]
      )

      insert(:log_line,
        step: step,
        run: run,
        message: "Processing data...",
        timestamp: ~U[2024-01-01 10:00:01Z]
      )

      insert(:log_line,
        step: step,
        run: run,
        message: "Job completed successfully",
        timestamp: ~U[2024-01-01 10:00:02Z]
      )

      session =
        insert(:chat_session,
          user: user,
          job: job,
          meta: %{"follow_run_id" => run.id}
        )

      enriched = AiAssistant.enrich_session_with_job_context(session)

      # Assert that logs contain our messages
      assert enriched.logs =~ "Starting job execution"
      assert enriched.logs =~ "Processing data..."
      assert enriched.logs =~ "Job completed successfully"

      # Also verify the order is preserved
      assert enriched.logs ==
               "Starting job execution\nProcessing data...\nJob completed successfully"
    end

    test "returns session unchanged when job_id is nil", %{user: user} do
      session = insert(:chat_session, user: user, job_id: nil)

      enriched = AiAssistant.enrich_session_with_job_context(session)

      assert enriched == session
    end

    test "handles missing job gracefully when enriching", %{
      user: user
    } do
      # Create session with a non-existent job_id
      fake_job_id = Ecto.UUID.generate()

      session = %Lightning.AiAssistant.ChatSession{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        session_type: "job_code",
        title: "Test Session",
        job_id: fake_job_id,
        meta: %{},
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      # Enrich should handle gracefully when job doesn't exist in database
      enriched = AiAssistant.enrich_session_with_job_context(session)

      # Session should be returned as-is without enrichment (nil values)
      assert enriched.job_id == fake_job_id
      assert enriched.expression == nil
      assert enriched.adaptor == nil
    end

    test "adds run logs for unsaved jobs when follow_run_id is in meta", %{
      user: user,
      workflow: %{jobs: [job | _]} = workflow
    } do
      # Generate a job_id that doesn't exist in the database (unsaved job)
      unsaved_job_id = Ecto.UUID.generate()

      work_order = insert(:workorder, workflow: workflow)

      run =
        insert(:run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: job
        )

      # Create a step with the unsaved job_id (not in Jobs table)
      # We use build(:step) and manually set the job_id, then insert it
      step =
        build(:step, job: nil)
        |> Ecto.Changeset.change(%{job_id: unsaved_job_id})
        |> Lightning.Repo.insert!()

      insert(:run_step, run: run, step: step)

      insert(:log_line,
        step: step,
        run: run,
        message: "Unsaved job log 1",
        timestamp: ~U[2024-01-01 10:00:00Z]
      )

      insert(:log_line,
        step: step,
        run: run,
        message: "Unsaved job log 2",
        timestamp: ~U[2024-01-01 10:00:01Z]
      )

      # Create session with unsaved_job data
      session =
        insert(:chat_session,
          user: user,
          job_id: nil,
          meta: %{
            "unsaved_job" => %{
              "id" => unsaved_job_id,
              "name" => "Unsaved Test Job",
              "body" => "console.log('test');",
              "adaptor" => "@openfn/language-http@latest",
              "workflow_id" => workflow.id
            },
            "follow_run_id" => run.id
          }
        )

      enriched = AiAssistant.enrich_session_with_job_context(session)

      # Assert that logs contain our messages
      assert enriched.logs =~ "Unsaved job log 1"
      assert enriched.logs =~ "Unsaved job log 2"

      # Also verify the order is preserved
      assert enriched.logs == "Unsaved job log 1\nUnsaved job log 2"

      # Verify the job body and adaptor are set correctly
      assert enriched.expression == "console.log('test');"

      assert enriched.adaptor ==
               Lightning.AdaptorRegistry.resolve_adaptor(
                 "@openfn/language-http@latest"
               )
    end
  end

  describe "retry_message/1" do
    test "resets message status to pending and enqueues for reprocessing", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      session = insert(:chat_session, user: user, job: job)

      message =
        insert(:chat_message,
          content: "test",
          role: :user,
          user: user,
          status: :error,
          chat_session: session
        )

      assert {:ok, {updated_message, _oban_job}} =
               AiAssistant.retry_message(message)

      assert updated_message.status == :pending

      assert_enqueued(
        worker: Lightning.AiAssistant.MessageProcessor,
        args: %{"message_id" => message.id}
      )
    end

    test "works with messages in different error states", %{
      user: user,
      workflow: %{jobs: [job | _]}
    } do
      session = insert(:chat_session, user: user, job: job)

      for initial_status <- [:error, :cancelled, :success] do
        message =
          insert(:chat_message,
            content: "test #{initial_status}",
            role: :user,
            user: user,
            status: initial_status,
            chat_session: session
          )

        assert {:ok, {updated_message, _}} = AiAssistant.retry_message(message)
        assert updated_message.status == :pending
      end
    end
  end

  describe "enabled?/0" do
    test "returns true when endpoint and api_key are configured" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      assert AiAssistant.enabled?() == true
    end

    test "returns false when endpoint is missing" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> nil
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when api_key is missing" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> nil
          :timeout -> 5_000
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when both endpoint and api_key are missing" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> nil
          :ai_assistant_api_key -> nil
          :timeout -> 5_000
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when endpoint is not a binary" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> 123
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      assert AiAssistant.enabled?() == false
    end

    test "returns false when api_key is not a binary" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> 123
          :timeout -> 5_000
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

  describe "create_workflow_session/5" do
    test "creates a new workflow session", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        content = "Create a workflow for data sync"

        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   workflow,
                   user,
                   content
                 )

        assert session.project_id == project.id
        assert session.user_id == user.id
        assert session.workflow_id == workflow.id
        assert session.session_type == "workflow_template"
        assert length(session.messages) == 1
        assert hd(session.messages).content == content
      end)
    end

    test "creates session without workflow", %{
      user: user,
      project: project
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   nil,
                   user,
                   "Create new workflow"
                 )

        assert session.project_id == project.id
        assert session.workflow_id == nil
      end)
    end

    test "accepts optional parameters", %{
      user: user,
      project: project
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        meta = %{"key" => "value"}
        code = "workflow code"

        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   nil,
                   user,
                   "test",
                   meta: meta,
                   code: code
                 )

        assert session.meta == meta
        [message] = session.messages
        assert message.code == code
      end)
    end

    test "generates a UUID for new workflow session", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   workflow,
                   user,
                   "test"
                 )

        assert is_binary(session.id)
        assert {:ok, _uuid} = Ecto.UUID.cast(session.id)
      end)
    end

    test "initializes meta as empty map when not provided", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   workflow,
                   user,
                   "test"
                 )

        assert session.meta == %{}
      end)
    end

    test "creates title from content", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        content = "Create a data processing workflow for customer data"

        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   workflow,
                   user,
                   content
                 )

        assert session.title == "Create a data processing workflow for"
      end)
    end

    test "creates workflow session with initial user message", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   workflow,
                   user,
                   "test message"
                 )

        assert session.project_id == project.id
        assert session.workflow_id == workflow.id
        assert session.user_id == user.id
        assert session.session_type == "workflow_template"

        [initial_message] = session.messages
        assert initial_message.role == :user
        assert initial_message.content == "test message"
        assert initial_message.user_id == user.id
        assert initial_message.status == :pending

        assert Repo.get!(Lightning.AiAssistant.ChatMessage, initial_message.id)
      end)
    end

    test "enqueues message for processing when creating workflow session", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   workflow,
                   user,
                   "test message"
                 )

        [initial_message] = session.messages

        assert_enqueued(
          worker: Lightning.AiAssistant.MessageProcessor,
          args: %{"message_id" => initial_message.id}
        )
      end)
    end

    test "enqueues message for processing", %{
      user: user,
      project: project
    } do
      # Use Oban's manual testing mode to ensure jobs stay enqueued
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, session} =
                 AiAssistant.create_workflow_session(
                   project,
                   nil,
                   nil,
                   user,
                   "test"
                 )

        [message] = session.messages

        # Verify the job was enqueued
        assert_enqueued(
          worker: Lightning.AiAssistant.MessageProcessor,
          args: %{"message_id" => message.id}
        )
      end)
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

  describe "cleanup_unsaved_job_sessions/1" do
    test "updates sessions with unsaved job data to use real job_id", %{
      user: user,
      project: project
    } do
      # Create workflow
      workflow = insert(:workflow, project: project)

      # Generate unsaved job ID
      unsaved_job_id = Ecto.UUID.generate()

      # Create session with unsaved job metadata
      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job_id: nil,
          meta: %{
            "unsaved_job" => %{
              "id" => unsaved_job_id,
              "name" => "Unsaved Job",
              "body" => "console.log('test');",
              "adaptor" => "@openfn/language-common@1.0.0",
              "workflow_id" => workflow.id
            }
          }
        )

      # Now "save" the workflow which creates a real job with the unsaved_job_id
      _job =
        insert(:job,
          id: unsaved_job_id,
          workflow: workflow,
          name: "Now Saved Job",
          body: "console.log('saved');",
          adaptor: "@openfn/language-common@1.0.0"
        )

      # Reload workflow with jobs
      workflow = Lightning.Repo.preload(workflow, :jobs, force: true)

      # Run cleanup
      assert {:ok, 1} = AiAssistant.cleanup_unsaved_job_sessions(workflow)

      # Verify session was updated
      updated_session =
        Lightning.Repo.get!(Lightning.AiAssistant.ChatSession, session.id)

      assert updated_session.job_id == unsaved_job_id
      refute Map.has_key?(updated_session.meta, "unsaved_job")
    end

    test "returns count of 0 when no sessions match", %{workflow: workflow} do
      assert {:ok, 0} = AiAssistant.cleanup_unsaved_job_sessions(workflow)
    end
  end

  describe "cleanup_unsaved_workflow_sessions/1" do
    test "updates sessions with unsaved workflow data to use real workflow_id",
         %{
           user: user,
           project: project
         } do
      # Create a workflow that we'll treat as "newly saved"
      workflow = insert(:workflow, project: project)

      # Create session with unsaved workflow metadata referencing this workflow's ID
      session =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          workflow_id: nil,
          meta: %{
            "unsaved_workflow" => %{
              "id" => workflow.id,
              "name" => "Unsaved Workflow"
            }
          }
        )

      # Run cleanup
      assert {:ok, 1} = AiAssistant.cleanup_unsaved_workflow_sessions(workflow)

      # Verify session was updated
      updated_session =
        Lightning.Repo.get!(Lightning.AiAssistant.ChatSession, session.id)

      assert updated_session.workflow_id == workflow.id
      refute Map.has_key?(updated_session.meta, "unsaved_workflow")
    end

    test "returns count of 0 when no sessions match", %{workflow: workflow} do
      assert {:ok, 0} = AiAssistant.cleanup_unsaved_workflow_sessions(workflow)
    end
  end

  describe "enrich_session_with_job_context/1 edge cases" do
    test "enriches session with runtime_context metadata", %{user: user} do
      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job_id: nil,
          meta: %{
            "runtime_context" => %{
              "job_body" => "fn(state => state);",
              "job_adaptor" => "@openfn/language-http@1.0.0",
              "job_name" => "Runtime Job",
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          }
        )

      enriched = AiAssistant.enrich_session_with_job_context(session)

      assert enriched.expression == "fn(state => state);"
      assert enriched.adaptor == "@openfn/language-http@1.0.0"
    end

    test "enriches session with unsaved_job metadata", %{user: user} do
      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job_id: nil,
          meta: %{
            "unsaved_job" => %{
              "id" => Ecto.UUID.generate(),
              "body" => "console.log('test');",
              "adaptor" => "@openfn/language-common@1.0.0"
            }
          }
        )

      enriched = AiAssistant.enrich_session_with_job_context(session)

      assert enriched.expression == "console.log('test');"
      assert enriched.adaptor == "@openfn/language-common@1.0.0"
    end

    test "returns session with context when job is in session", %{user: user} do
      # When a session has a job through the factory, it gets enriched
      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code"
        )

      enriched = AiAssistant.enrich_session_with_job_context(session)

      # Verify it returns the session (enriched or not)
      assert enriched.id == session.id
      assert enriched.session_type == "job_code"
    end
  end

  describe "list_sessions/3 with Project resource" do
    test "lists workflow template sessions for project", %{
      user: user,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      _session1 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          workflow_id: workflow.id
        )

      _session2 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          workflow_id: nil
        )

      # List sessions using Project struct
      %{sessions: sessions} = AiAssistant.list_sessions(project, :desc, [])

      assert length(sessions) == 2
    end

    test "filters workflow template sessions by workflow", %{
      user: user,
      project: project
    } do
      workflow1 = insert(:workflow, project: project)
      workflow2 = insert(:workflow, project: project)

      _session1 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          workflow_id: workflow1.id
        )

      _session2 =
        insert(:chat_session,
          user: user,
          project: project,
          session_type: "workflow_template",
          workflow_id: workflow2.id
        )

      # Filter by specific workflow
      %{sessions: sessions} =
        AiAssistant.list_sessions(project, :desc, workflow: workflow1)

      assert length(sessions) == 1
      assert hd(sessions).workflow_id == workflow1.id
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
          :timeout -> 5_000
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
               AiAssistant.query_workflow(session, "Create workflow")

      assert length(updated_session.messages) == 1
    end

    test "handles errors from workflow chat service", %{
      user: user,
      project: project,
      workflow: _workflow
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
          :timeout -> 5_000
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
               AiAssistant.query_workflow(session, "Create workflow")
    end

    test "handles timeout errors in workflow query", %{
      user: user,
      project: project,
      workflow: _workflow
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
          :timeout -> 5_000
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :timeout}
      end)

      assert {:error, "Request timed out. Please try again."} =
               AiAssistant.query_workflow(session, "Create workflow")
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
          :timeout -> 5_000
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, :econnrefused}
      end)

      assert {:error, "Unable to reach the AI server. Please try again later."} =
               AiAssistant.query_workflow(session, "Create workflow")
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
          :timeout -> 5_000
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
        {:error, %{unexpected: "error"}}
      end)

      assert {:error, "Oops! Something went wrong. Please try again."} =
               AiAssistant.query_workflow(session, "Create workflow")
    end

    test "passes options to workflow service", %{
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
          :timeout -> 5_000
        end
      end)

      validation_errors = "Invalid cron expression: '0 0 * * 8'"
      existing_code = "name: Test\njobs: []"

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post, body: body},
                                             _opts ->
        decoded = Jason.decode!(body)
        assert decoded["errors"] == validation_errors
        assert decoded["existing_yaml"] == existing_code

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
        AiAssistant.query_workflow(session, "Fix the errors",
          errors: validation_errors,
          code: existing_code
        )
    end

    test "passes workflow code as option to workflow service", %{
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
      name: Test Workflow
      jobs: []
      """

      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
          :timeout -> 5_000
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :post, body: body},
                                             _opts ->
        decoded = Jason.decode!(body)
        assert decoded["existing_yaml"] == workflow_yaml

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "response" => "Updated workflow",
             "response_yaml" => "workflow: updated"
           }
         }}
      end)

      # Pass the YAML as an option
      {:ok, _} =
        AiAssistant.query_workflow(
          session,
          "Update the workflow",
          code: workflow_yaml
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

    test "filters workflow sessions by workflow_id when provided", %{
      user: user,
      project: project,
      workflow: workflow
    } do
      # Session with workflow
      _with_workflow =
        insert(:chat_session,
          user: user,
          project: project,
          workflow: workflow,
          session_type: "workflow_template"
        )

      # Session without workflow
      _without_workflow =
        insert(:chat_session,
          user: user,
          project: project,
          workflow_id: nil,
          session_type: "workflow_template"
        )

      # List with workflow filter
      result_with_workflow =
        AiAssistant.list_sessions(project, :desc,
          workflow: workflow,
          offset: 0,
          limit: 10
        )

      assert length(result_with_workflow.sessions) == 1
      assert hd(result_with_workflow.sessions).workflow_id == workflow.id

      # List without workflow filter (nil workflow)
      result_without_workflow =
        AiAssistant.list_sessions(project, :desc,
          workflow: nil,
          offset: 0,
          limit: 10
        )

      assert length(result_without_workflow.sessions) == 1
      assert hd(result_without_workflow.sessions).workflow_id == nil
    end

    test "returns empty results when no sessions exist", %{project: project} do
      result = AiAssistant.list_sessions(project, :desc, offset: 0, limit: 10)

      assert result.sessions == []
      assert result.pagination.total_count == 0
      assert result.pagination.has_next_page == false
    end

    test "only returns job sessions for job queries", %{
      user: user,
      project: project,
      workflow: %{jobs: [job | _]}
    } do
      # Create a workflow session (should not be returned)
      insert(:chat_session,
        user: user,
        project: project,
        session_type: "workflow_template"
      )

      # Create a job session
      insert(:chat_session, user: user, job: job)

      result = AiAssistant.list_sessions(job, :desc, offset: 0, limit: 10)

      assert length(result.sessions) == 1
      assert hd(result.sessions).job_id == job.id
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
