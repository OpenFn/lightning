defmodule Lightning.ApolloClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias Lightning.ApolloClient

  setup :verify_on_exit!

  describe "job_chat/2" do
    test "sends a job chat request with all parameters" do
      stub_apollo_config()

      context = %{
        expression: "fn(state) => http.get('/api/data')",
        adaptor: "@openfn/language-http"
      }

      history = [%{role: "user", content: "How do I make requests?"}]
      meta = %{session_id: "abc123"}

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/job_chat"

        decoded_body = Jason.decode!(body)
        assert decoded_body["api_key"] == "api_key"
        assert decoded_body["content"] == "Add error handling"

        assert decoded_body["context"] == %{
                 "expression" => "fn(state) => http.get('/api/data')",
                 "adaptor" => "@openfn/language-http"
               }

        assert decoded_body["history"] == [
                 %{"role" => "user", "content" => "How do I make requests?"}
               ]

        assert decoded_body["meta"] == %{"session_id" => "abc123"}
        assert decoded_body["suggest_code"] == true

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "history" => [
               %{"role" => "user", "content" => "Add error handling"},
               %{
                 "role" => "assistant",
                 "content" => "Here's how to add error handling..."
               }
             ],
             "usage" => %{"tokens" => 150, "cost" => 0.003}
           }
         }}
      end)

      {:ok, response} =
        ApolloClient.job_chat("Add error handling",
          context: context,
          history: history,
          meta: meta
        )

      assert response.status == 200
      assert length(response.body["history"]) == 2
      assert response.body["usage"]["tokens"] == 150
    end

    test "sends job chat with minimal parameters" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{body: body} = env
        decoded_body = Jason.decode!(body)

        assert decoded_body["content"] == "Help me debug"
        assert decoded_body["context"] == %{}
        assert decoded_body["history"] == []
        assert decoded_body["meta"] == %{}
        assert decoded_body["suggest_code"] == true

        {:ok, %Tesla.Env{status: 200, body: %{"response" => "Debug help..."}}}
      end)

      {:ok, response} = ApolloClient.job_chat("Help me debug")
      assert response.body["response"] == "Debug help..."
    end

    test "handles job chat error responses" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok,
         %Tesla.Env{status: 400, body: %{"message" => "Invalid context format"}}}
      end)

      {:ok, response} =
        ApolloClient.job_chat("test", context: %{invalid: "context"})

      assert response.status == 400
      assert response.body["message"] == "Invalid context format"
    end

    test "handles network errors in job chat" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      {:error, :econnrefused} = ApolloClient.job_chat("test")
    end

    test "sends a query" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/job_chat"

        assert Jason.decode!(body) == %{
                 "api_key" => "api_key",
                 "content" => "foo",
                 "context" => %{},
                 "history" => [],
                 "meta" => %{},
                 "suggest_code" => true
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

      {:ok, response} = ApolloClient.job_chat("foo")

      assert response.body
    end

    test "sends a query with all parameters" do
      stub_apollo_config()

      context = %{
        expression: "fn(state) => state",
        adaptor: "@openfn/language-http"
      }

      history = [
        %{role: "user", content: "Previous question"},
        %{role: "assistant", content: "Previous answer"}
      ]

      meta = %{session_id: "123", user_id: "456"}

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/job_chat"

        assert Jason.decode!(body) == %{
                 "api_key" => "api_key",
                 "content" => "How do I handle errors?",
                 "context" => %{
                   "expression" => "fn(state) => state",
                   "adaptor" => "@openfn/language-http"
                 },
                 "history" => [
                   %{"role" => "user", "content" => "Previous question"},
                   %{"role" => "assistant", "content" => "Previous answer"}
                 ],
                 "meta" => %{"session_id" => "123", "user_id" => "456"},
                 "suggest_code" => true
               }

        {:ok, %Tesla.Env{status: 200, body: %{"response" => "Handle errors..."}}}
      end)

      {:ok, response} =
        ApolloClient.job_chat("How do I handle errors?",
          context: context,
          history: history,
          meta: meta
        )

      assert response.body["response"] == "Handle errors..."
    end

    test "sends a query with partial parameters" do
      stub_apollo_config()

      context = %{expression: "console.log('hello')"}

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{body: body} = env

        assert Jason.decode!(body) == %{
                 "api_key" => "api_key",
                 "content" => "Test content",
                 "context" => %{"expression" => "console.log('hello')"},
                 "history" => [],
                 "meta" => %{},
                 "suggest_code" => true
               }

        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      {:ok, _response} = ApolloClient.job_chat("Test content", context: context)
    end

    test "handles error responses" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok,
         %Tesla.Env{status: 500, body: %{"message" => "Internal server error"}}}
      end)

      {:ok, response} = ApolloClient.job_chat("test")
      assert response.status == 500
      assert response.body["message"] == "Internal server error"
    end

    test "handles network errors" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :timeout}
      end)

      {:error, :timeout} = ApolloClient.job_chat("test")
    end
  end

  describe "workflow_chat/5" do
    test "sends a workflow chat request with all parameters" do
      stub_apollo_config()

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
          code: "workflow: example",
          errors: "validation error",
          history: [%{role: "user", content: "previous"}],
          meta: %{key: "value"}
        )

      assert response.body["response"] == "Workflow created"
      assert response.body["response_yaml"] == "workflow: updated"
    end

    test "sends a workflow chat request with minimal parameters" do
      stub_apollo_config()

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
      stub_apollo_config()

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

    test "filters out nil parameters correctly" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{body: body} = env
        decoded_body = Jason.decode!(body)

        assert decoded_body == %{
                 "api_key" => "api_key",
                 "content" => "Create workflow",
                 "existing_yaml" => "workflow: existing",
                 "history" => [],
                 "meta" => %{}
               }

        refute Map.has_key?(decoded_body, "errors")

        {:ok, %Tesla.Env{status: 200, body: %{"response" => "success"}}}
      end)

      {:ok, _response} =
        ApolloClient.workflow_chat(
          "Create workflow",
          code: "workflow: existing",
          errors: nil,
          history: [],
          meta: %{}
        )
    end

    test "handles workflow chat with existing_yaml only" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{body: body} = env
        decoded_body = Jason.decode!(body)

        assert decoded_body["existing_yaml"] == "workflow: modify_this"
        refute Map.has_key?(decoded_body, "errors")

        {:ok,
         %Tesla.Env{status: 200, body: %{"response" => "Modified workflow"}}}
      end)

      {:ok, response} =
        ApolloClient.workflow_chat("Improve this",
          code: "workflow: modify_this"
        )

      assert response.body["response"] == "Modified workflow"
    end

    test "handles workflow chat with errors only" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{body: body} = env
        decoded_body = Jason.decode!(body)

        assert decoded_body["errors"] == "Invalid cron expression"
        refute Map.has_key?(decoded_body, "existing_yaml")

        {:ok, %Tesla.Env{status: 200, body: %{"response" => "Fixed errors"}}}
      end)

      {:ok, response} =
        ApolloClient.workflow_chat("Fix errors",
          errors: "Invalid cron expression"
        )

      assert response.body["response"] == "Fixed errors"
    end

    test "handles network errors in workflow chat" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :timeout}
      end)

      {:error, :timeout} = ApolloClient.workflow_chat("Create workflow")
    end

    test "handles various HTTP error codes" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 401, body: %{"message" => "Unauthorized"}}}
      end)

      {:ok, response} = ApolloClient.workflow_chat("test")
      assert response.status == 401

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok,
         %Tesla.Env{
           status: 503,
           body: %{"message" => "Service temporarily unavailable"}
         }}
      end)

      {:ok, response} = ApolloClient.workflow_chat("test")
      assert response.status == 503
    end
  end

  describe "test/0" do
    test "returns :ok when endpoint is available" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 200}}
      end)

      assert ApolloClient.test() == :ok
    end

    test "returns :error when endpoint is not available" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 404}}
      end)

      assert ApolloClient.test() == :error
    end

    test "returns :error when request fails" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:error, :econnrefused}
      end)

      assert ApolloClient.test() == :error
    end

    test "returns :ok for all 2xx status codes" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 201}}
      end)

      assert ApolloClient.test() == :ok

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 204}}
      end)

      assert ApolloClient.test() == :ok

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 299}}
      end)

      assert ApolloClient.test() == :ok
    end

    test "returns :error for non-2xx status codes" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 301}}
      end)

      assert ApolloClient.test() == :error

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 401}}
      end)

      assert ApolloClient.test() == :error

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:ok, %Tesla.Env{status: 500}}
      end)

      assert ApolloClient.test() == :error
    end

    test "makes request to correct endpoint" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get, url: url}, _opts ->
        assert url == "http://localhost:3000/"
        {:ok, %Tesla.Env{status: 200}}
      end)

      ApolloClient.test()
    end

    test "handles various network errors" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:error, :timeout}
      end)

      assert ApolloClient.test() == :error

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:error, :nxdomain}
      end)

      assert ApolloClient.test() == :error

      expect(Lightning.Tesla.Mock, :call, fn %{method: :get}, _opts ->
        {:error, :econnrefused}
      end)

      assert ApolloClient.test() == :error
    end
  end

  describe "client configuration" do
    test "all functions use the correct endpoint configuration" do
      custom_endpoint = "https://custom-apollo.example.com"

      stub_apollo_config(custom_endpoint, "custom_api_key")

      expect(Lightning.Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert String.starts_with?(url, custom_endpoint)
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      ApolloClient.job_chat("test")

      expect(Lightning.Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert String.starts_with?(url, custom_endpoint)
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      ApolloClient.workflow_chat("test")

      expect(Lightning.Tesla.Mock, :call, fn %{url: url}, _opts ->
        assert url == "#{custom_endpoint}/"
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      ApolloClient.test()
    end

    test "all functions use the correct API key" do
      custom_api_key = "sk-custom-api-key-12345"

      stub_apollo_config("http://localhost:3000", custom_api_key)

      expect(Lightning.Tesla.Mock, :call, fn %{body: body}, _opts ->
        decoded = Jason.decode!(body)
        assert decoded["api_key"] == custom_api_key
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      ApolloClient.job_chat("test")

      expect(Lightning.Tesla.Mock, :call, fn %{body: body}, _opts ->
        decoded = Jason.decode!(body)
        assert decoded["api_key"] == custom_api_key
        {:ok, %Tesla.Env{status: 200, body: %{}}}
      end)

      ApolloClient.workflow_chat("test")
    end
  end

  describe "legacy compatibility" do
    test "job_chat/2 is an alias for job_chat/4" do
      stub_apollo_config()

      context = %{expression: "test"}
      history = [%{role: "user", content: "test"}]
      meta = %{session_id: "123"}

      expect(Lightning.Tesla.Mock, :call, 2, fn %{body: body}, _opts ->
        decoded = Jason.decode!(body)
        assert decoded["content"] == "test query"
        assert decoded["context"] == %{"expression" => "test"}
        assert decoded["history"] == [%{"role" => "user", "content" => "test"}]
        assert decoded["meta"] == %{"session_id" => "123"}
        assert decoded["suggest_code"] == true
        {:ok, %Tesla.Env{status: 200, body: %{"response" => "test"}}}
      end)

      {:ok, response1} =
        ApolloClient.job_chat("test query",
          context: context,
          history: history,
          meta: meta
        )

      {:ok, response2} =
        ApolloClient.job_chat("test query",
          context: context,
          history: history,
          meta: meta
        )

      assert response1.body == response2.body
    end
  end

  # Private helper function to stub Apollo configuration
  defp stub_apollo_config(
         endpoint \\ "http://localhost:3000",
         api_key \\ "api_key"
       ) do
    Mox.stub(Lightning.MockConfig, :apollo, fn key ->
      case key do
        :endpoint -> endpoint
        :ai_assistant_api_key -> api_key
        :timeout -> 5_000
      end
    end)
  end
end
