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

  describe "endpoint_available?" do
    test "availability" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :openai_api_key -> "api_key"
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
          :openai_api_key -> "api_key"
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
  end

  describe "save_message/2" do
    test "calls limiter to increment ai queries when role is assistant" do
      user = insert(:user)

      %{id: job_id} = job = insert(:job, workflow: build(:workflow))

      session = insert(:chat_session, job: job, user: user)

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :increment_ai_queries,
        1,
        fn %{job_id: ^job_id} -> Ecto.Multi.new() end
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
        :increment_ai_queries,
        0,
        fn %{job_id: ^job_id} -> Ecto.Multi.new() end
      )

      AiAssistant.save_message(session, %{
        role: :user,
        content: "What if I want to deduplicate the headers?",
        user: user
      })
    end
  end
end
