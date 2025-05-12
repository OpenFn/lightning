defmodule Lightning.ApolloClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias Lightning.ApolloClient

  setup :verify_on_exit!

  describe "query/4" do
    test "sends a query" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/job_chat"

        assert Jason.decode!(body) == %{
                 "api_key" => "api_key",
                 "content" => "foo",
                 "context" => %{},
                 "history" => [],
                 "meta" => %{}
               }

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "history" => [
               %{"content" => "what?", "role" => "user"},
               %{
                 "content" =>
                   "Based on the provided guide and the API documentation for the OpenFn @openfn/language-common@1.14.0 adaptor, you can create jobs using the functions provided by the API to interact with different data sources and perform various operations.\n\nTo create a job using the HTTP adaptor, you can use functions like `get`, `post`, `put`, `patch`, `head`, and `options` to make HTTP requests. Here's an example job code using the HTTP adaptor:\n\n```javascript\nconst { get, post, each, dataValue } = require('@openfn/language-common');\n\nexecute(\n  get('/patients'),\n  each('$.data.patients[*]', (item, index) => {\n    item.id = `item-${index}`;\n  }),\n  post('/patients', dataValue('patients'))\n);\n```\n\nIn this example, the job first fetches patient data using a GET request, then iterates over each patient to modify their ID, and finally posts the modified patient data back.\n\nYou can similarly create jobs using the Salesforce adaptor or the ODK adaptor by utilizing functions like `upsert`, `create`, `fields`, `field`, etc., as shown in the provided examples.\n\nFeel free to ask if you have any specific questions or need help with",
                 "role" => "assistant"
               }
             ],
             "response" =>
               "Based on the provided guide and the API documentation for the OpenFn @openfn/language-common@1.14.0 adaptor, you can create jobs using the functions provided by the API to interact with different data sources and perform various operations.\n\nTo create a job using the HTTP adaptor, you can use functions like `get`, `post`, `put`, `patch`, `head`, and `options` to make HTTP requests. Here's an example job code using the HTTP adaptor:\n\n```javascript\nconst { get, post, each, dataValue } = require('@openfn/language-common');\n\nexecute(\n  get('/patients'),\n  each('$.data.patients[*]', (item, index) => {\n    item.id = `item-${index}`;\n  }),\n  post('/patients', dataValue('patients'))\n);\n```\n\nIn this example, the job first fetches patient data using a GET request, then iterates over each patient to modify their ID, and finally posts the modified patient data back.\n\nYou can similarly create jobs using the Salesforce adaptor or the ODK adaptor by utilizing functions like `upsert`, `create`, `fields`, `field`, etc., as shown in the provided examples.\n\nFeel free to ask if you have any specific questions or need help with"
           }
         }}
      end)

      {:ok, response} = ApolloClient.query("foo")

      assert response.body
    end
  end

  describe "workflow_chat/5" do
    test "sends a workflow chat request with all parameters" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/workflow_chat"

        assert Jason.decode!(body) == %{
                 "api_key" => "api_key",
                 "content" => "Create workflow",
                 "existing_yaml" => "workflow: example",
                 "errors" => "validation error",
                 "history" => [%{"role" => "user", "content" => "previous"}],
                 "meta" => %{"key" => "value"}
               }

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "response" => "Workflow created",
             "response_yaml" => "workflow: updated",
             "usage" => %{"tokens" => 100}
           }
         }}
      end)

      {:ok, response} =
        ApolloClient.workflow_chat(
          "Create workflow",
          "workflow: example",
          "validation error",
          [%{role: "user", content: "previous"}],
          %{key: "value"}
        )

      assert response.body["response"] == "Workflow created"
      assert response.body["response_yaml"] == "workflow: updated"
    end

    test "sends a workflow chat request with minimal parameters" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/workflow_chat"

        assert Jason.decode!(body) == %{
                 "api_key" => "api_key",
                 "content" => "Create workflow",
                 "history" => [],
                 "meta" => %{}
               }

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "response" => "Workflow created",
             "response_yaml" => "workflow: new",
             "usage" => %{"tokens" => 50}
           }
         }}
      end)

      {:ok, response} = ApolloClient.workflow_chat("Create workflow")

      assert response.body["response"] == "Workflow created"
      assert response.body["response_yaml"] == "workflow: new"
    end

    test "handles error responses" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok,
         %Tesla.Env{
           status: 400,
           body: %{"message" => "Invalid request"}
         }}
      end)

      {:ok, response} = ApolloClient.workflow_chat("Create workflow")
      assert response.status == 400
      assert response.body["message"] == "Invalid request"
    end
  end

  describe "test/0" do
    test "returns :ok when endpoint is available" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 200}}
      end)

      assert ApolloClient.test() == :ok
    end

    test "returns :error when endpoint is not available" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 404}}
      end)

      assert ApolloClient.test() == :error
    end

    test "returns :error when request fails" do
      Mox.stub(Lightning.MockConfig, :apollo, fn key ->
        case key do
          :endpoint -> "http://localhost:3000"
          :ai_assistant_api_key -> "api_key"
        end
      end)

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:error, :econnrefused}
      end)

      assert ApolloClient.test() == :error
    end
  end
end
