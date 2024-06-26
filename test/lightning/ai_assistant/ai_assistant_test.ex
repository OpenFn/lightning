defmodule Lightning.AiAssistantTest do
  use ExUnit.Case, async: true
  import Mox

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.Session

  setup :verify_on_exit!

  describe "Session" do
    test "creation" do
      session = Session.new("fn()", "@openfn/language-common@latest")

      assert session.adaptor == "@openfn/language-common@1.6.2"
      assert session.expression == "fn()"
      assert session.history == []
    end

    test "put_history" do
      session =
        Session.new("fn()", "@openfn/language-common@latest")
        |> Session.put_history([%{role: :user, content: "fn()"}])

      assert session.history == [%{role: :user, content: "fn()"}]
    end

    test "put_expression" do
      session =
        Session.new("fn()", "@openfn/language-common@latest")
        |> Session.put_expression("fn(state => state)")

      assert session.expression == "fn(state => state)"
    end
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

  test "query" do
    session =
      AiAssistant.new_session(%Lightning.Workflows.Job{
        body: "fn()",
        adaptor: "@openfn/language-common@latest"
      })

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

    {:ok, session} = AiAssistant.query(session, "foo")

    assert session.history ==
             reply["history"]
             |> Enum.map(fn h -> %{role: h["role"], content: h["content"]} end)
  end

  test "authorized?" do
    assert AiAssistant.authorized?(%Lightning.Accounts.User{role: :superuser})
    refute AiAssistant.authorized?(%Lightning.Accounts.User{role: :user})
  end

  test "new_session" do
    job = %Lightning.Workflows.Job{
      body: "fn()",
      adaptor: "@openfn/language-common@latest"
    }

    session = AiAssistant.new_session(job)

    assert session.adaptor == "@openfn/language-common@1.6.2"
    assert session.expression == "fn()"
    assert session.history == []
  end
end
