defmodule Lightning.ApolloClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias Lightning.ApolloClient

  setup :verify_on_exit!

  test "sends a query" do
    Mox.stub(Lightning.MockConfig, :apollo, fn key ->
      case key do
        :endpoint -> "http://localhost:3000"
        :openai_api_key -> "api_key"
      end
    end)

    expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
      %{method: :post, url: url, body: body} = env
      assert url == "http://localhost:3000/services/job_chat"

      assert Jason.decode!(body) == %{
               "api_key" => "api_key",
               "content" => "foo",
               "context" => %{},
               "history" => []
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
