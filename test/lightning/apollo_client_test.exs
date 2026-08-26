defmodule Lightning.ApolloClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias Lightning.ApolloClient

  setup :verify_on_exit!

  describe "job_chat_stream/2" do
    test "sends streaming request with correct payload and endpoint" do
      stub_apollo_config()

      context = %{
        expression: "fn(state) => state",
        adaptor: "@openfn/language-http"
      }

      history = [%{role: "user", content: "previous"}]
      meta = %{session_id: "abc"}

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/job_chat/stream"

        decoded = Jason.decode!(body)
        assert decoded["content"] == "Help me"
        assert decoded["stream"] == true
        assert decoded["suggest_code"] == true
        assert decoded["api_key"] == "api_key"

        assert decoded["context"] == %{
                 "expression" => "fn(state) => state",
                 "adaptor" => "@openfn/language-http"
               }

        assert decoded["history"] == [
                 %{"role" => "user", "content" => "previous"}
               ]

        assert decoded["meta"] == %{"session_id" => "abc"}

        {:ok,
         %Tesla.Env{
           status: 200,
           headers: [{"content-type", "text/event-stream"}],
           body: "event: complete\ndata: {}\n\n"
         }}
      end)

      {:ok, response} =
        ApolloClient.job_chat_stream("Help me",
          context: context,
          history: history,
          meta: meta
        )

      assert response.status == 200
    end

    test "sends with default parameters" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{body: body}, _opts ->
        decoded = Jason.decode!(body)
        assert decoded["context"] == %{}
        assert decoded["history"] == []
        assert decoded["meta"] == %{}
        assert decoded["stream"] == true

        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.job_chat_stream("test")
    end

    test "handles network errors" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = ApolloClient.job_chat_stream("test")
    end

    test "sends metrics_opt_in and meta with langfuse keys" do
      stub_apollo_config()

      meta = %{
        "session_id" => "sess-3",
        "user" => %{"id" => "u-3", "persona" => "core-contributor"}
      }

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        decoded = Jason.decode!(env.body)
        assert decoded["metrics_opt_in"] == true
        assert decoded["meta"] == meta
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} =
        ApolloClient.job_chat_stream("hi", meta: meta, metrics_opt_in: true)
    end

    test "omits metrics_opt_in when not given" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        refute Map.has_key?(Jason.decode!(env.body), "metrics_opt_in")
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.job_chat_stream("hi")
    end
  end

  describe "workflow_chat_stream/2" do
    test "sends streaming request with all parameters" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/workflow_chat/stream"

        decoded = Jason.decode!(body)
        assert decoded["content"] == "Create workflow"
        assert decoded["stream"] == true
        assert decoded["existing_yaml"] == "workflow: old"
        assert decoded["errors"] == "invalid cron"
        assert decoded["api_key"] == "api_key"

        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} =
        ApolloClient.workflow_chat_stream("Create workflow",
          code: "workflow: old",
          errors: "invalid cron",
          history: [],
          meta: %{}
        )
    end

    test "filters nil values from payload" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{body: body}, _opts ->
        decoded = Jason.decode!(body)
        refute Map.has_key?(decoded, "existing_yaml")
        refute Map.has_key?(decoded, "errors")
        assert decoded["stream"] == true

        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.workflow_chat_stream("Create workflow")
    end

    test "handles network errors" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} =
               ApolloClient.workflow_chat_stream("test")
    end

    test "sends metrics_opt_in and meta with langfuse keys" do
      stub_apollo_config()

      meta = %{
        "session_id" => "sess-4",
        "user" => %{"id" => "u-4", "persona" => "core-contributor"}
      }

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        decoded = Jason.decode!(env.body)
        assert decoded["metrics_opt_in"] == true
        assert decoded["meta"] == meta
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} =
        ApolloClient.workflow_chat_stream("hi",
          meta: meta,
          metrics_opt_in: true
        )
    end

    test "omits metrics_opt_in when not given" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        refute Map.has_key?(Jason.decode!(env.body), "metrics_opt_in")
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.workflow_chat_stream("hi")
    end
  end

  describe "global_chat_stream/2" do
    test "sends streaming request with all parameters" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        %{method: :post, url: url, body: body} = env
        assert url == "http://localhost:3000/services/global_chat/stream"

        decoded = Jason.decode!(body)
        assert decoded["content"] == "Help me build a workflow"
        assert decoded["api_key"] == "api_key"
        assert decoded["workflow_yaml"] == "workflow:\n  name: test"
        assert decoded["page"] == "/projects/abc/workflows/def/jobs/ghi"
        assert decoded["options"] == %{"stream" => true}

        assert decoded["history"] == [
                 %{"role" => "user", "content" => "previous"}
               ]

        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} =
        ApolloClient.global_chat_stream("Help me build a workflow",
          workflow_yaml: "workflow:\n  name: test",
          page: "/projects/abc/workflows/def/jobs/ghi",
          history: [%{role: "user", content: "previous"}]
        )
    end

    test "filters nil values from payload" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn %{body: body}, _opts ->
        decoded = Jason.decode!(body)
        refute Map.has_key?(decoded, "workflow_yaml")
        refute Map.has_key?(decoded, "page")
        assert decoded["options"] == %{"stream" => true}
        assert decoded["content"] == "Hello"
        assert decoded["history"] == []

        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.global_chat_stream("Hello")
    end

    test "handles network errors" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               ApolloClient.global_chat_stream("test")
    end

    test "sends metrics_opt_in and meta with langfuse keys" do
      stub_apollo_config()

      meta = %{
        "session_id" => "sess-5",
        "user" => %{"id" => "u-5", "persona" => "core-contributor"}
      }

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        decoded = Jason.decode!(env.body)
        assert decoded["metrics_opt_in"] == true
        assert decoded["meta"] == meta
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} =
        ApolloClient.global_chat_stream("hi",
          meta: meta,
          metrics_opt_in: true
        )
    end

    test "forwards meta when supplied" do
      stub_apollo_config()

      meta = %{"session_id" => "sess-2"}

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert Jason.decode!(env.body)["meta"] == meta
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.global_chat_stream("hi", meta: meta)
    end

    test "omits metrics_opt_in when not given" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        refute Map.has_key?(Jason.decode!(env.body), "metrics_opt_in")
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.global_chat_stream("hi")
    end

    test "forwards attachments" do
      stub_apollo_config()

      attachments = [
        %{
          "type" => "log",
          "content" => [%{"job_id" => "j-1", "level" => "error"}]
        },
        %{"type" => "input_dataclip", "content" => %{"a" => "string"}}
      ]

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert Jason.decode!(env.body)["attachments"] == attachments
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.global_chat_stream("hi", attachments: attachments)
    end

    test "sends an empty attachments list when none are given" do
      stub_apollo_config()

      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert Jason.decode!(env.body)["attachments"] == []
        {:ok, %Tesla.Env{status: 200, body: ""}}
      end)

      {:ok, _} = ApolloClient.global_chat_stream("hi")
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
