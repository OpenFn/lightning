defmodule Lightning.AdaptorRegistryTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Lightning.AdaptorRegistry

  describe "fetch/0" do
    # AdaptorRegistry is a GenServer, and so stubbed (external) functions must 
    # be mocked globally. See: https://github.com/edgurgel/mimic#private-and-global-mode
    setup :set_mimic_from_context

    setup do
      stub(:hackney)

      :ok
    end

    test "retrieves a list of adaptors" do
      # :hackney.request(request.method, request.url, request.headers, request.body, hn_options)
      expect(:hackney, :request, fn
        :get, "https://registry.npmjs.org/-/user/openfn/package", [], "", [pool: :default] ->
          {:ok, 200, "headers", :client}
      end)

      expected_adaptors = [
        "@openfn/language-asana",
        "@openfn/language-common",
        "@openfn/language-commcare",
        "@openfn/language-dhis2",
        "@openfn/language-http",
        "@openfn/language-salesforce"
      ]

      stub(:hackney, :body, fn :adaptor, _timeout ->
        {:ok, File.read!("test/fixtures/language-common-npm.json")}
      end)

      stub(:hackney, :request, fn
        :get, "https://registry.npmjs.org/" <> adaptor, [], "", [pool: :default] ->
          assert adaptor in expected_adaptors
          {:ok, 200, "headers", :adaptor}
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok,
         ~S[{"@openfn/language-common":"write","@openfn/devtools":"write","@openfn/language-http":"write","@openfn/core":"write","@openfn/simple-ast":"write","@openfn/language-dhis2":"write","@openfn/react-json-view":"write","@openfn/language-template":"write","@openfn/language-commcare":"write","@openfn/doclet-query":"write","@openfn/language-salesforce":"write","@openfn/language-asana":"write","@openfn/language-devtools":"write"}]}
      end)

      {:ok, _pid} = AdaptorRegistry.start_link()

      results = AdaptorRegistry.all()

      assert length(results) == 6

      assert %{
               name: "@openfn/language-common",
               repo: "git+https://github.com/OpenFn/language-common.git",
               latest: "1.6.2",
               versions: [
                 %{version: "1.1.0"},
                 %{version: "1.1.1"},
                 %{version: "1.2.0"},
                 %{version: "1.2.1"},
                 %{version: "1.2.2"},
                 %{version: "1.2.4"},
                 %{version: "1.2.5"},
                 %{version: "1.2.6"},
                 %{version: "1.2.7"},
                 %{version: "1.2.8"},
                 %{version: "1.4.0"},
                 %{version: "1.4.1"},
                 %{version: "1.4.2"},
                 %{version: "1.5.0"},
                 %{version: "1.6.0"},
                 %{version: "1.6.1"},
                 %{version: "1.6.2"}
               ]
             } in results
    end
  end
end
