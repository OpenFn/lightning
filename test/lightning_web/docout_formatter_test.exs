defmodule LightningWeb.DocoutFormatterTest do
  use ExUnit.Case, async: true

  alias LightningWeb.DocoutFormatter

  describe "format/1" do
    test "formats a complete module with functions" do
      doc_list = [
        {TestModule, %{"en" => "Test module doc"}, %{},
         [
           {{:function, :test_func, 2}, %{"en" => "Test function doc"},
            %{deprecated: "Use new_func/2"}},
           {{:function, :hidden_func, 1}, :hidden, %{}}
         ]}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert module_doc["module"] == "TestModule"
      assert module_doc["moduledoc"] == "Test module doc"
      assert [func] = module_doc["functions"]
      assert func["name"] == "test_func"
      assert func["arity"] == 2
      assert func["doc"] == "Test function doc"
      assert func["metadata"]["deprecated"] == "Use new_func/2"
    end

    test "formats module with binary moduledoc" do
      doc_list = [
        {TestModule, "Simple string doc", %{}, []}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert module_doc["moduledoc"] == "Simple string doc"
    end

    test "formats module with nil moduledoc" do
      doc_list = [
        {TestModule, nil, %{}, []}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert is_nil(module_doc["moduledoc"])
    end

    test "formats module with :none moduledoc" do
      doc_list = [
        {TestModule, :none, %{}, []}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert is_nil(module_doc["moduledoc"])
    end

    test "filters out hidden functions" do
      doc_list = [
        {TestModule, "Module doc", %{},
         [
           {{:function, :visible, 1}, %{"en" => "Visible doc"}, %{}},
           {{:function, :hidden, 1}, :hidden, %{}},
           {{:function, :also_visible, 2}, %{"en" => "Also visible"}, %{}}
         ]}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert length(module_doc["functions"]) == 2
      function_names = Enum.map(module_doc["functions"], & &1["name"])
      assert "visible" in function_names
      assert "also_visible" in function_names
      refute "hidden" in function_names
    end

    test "filters out non-function entries" do
      doc_list = [
        {TestModule, "Module doc", %{},
         [
           {{:function, :my_func, 1}, %{"en" => "Function doc"}, %{}},
           {{:macro, :my_macro, 2}, %{"en" => "Macro doc"}, %{}},
           {{:type, :my_type, 0}, %{"en" => "Type doc"}, %{}}
         ]}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert [func] = module_doc["functions"]
      assert func["name"] == "my_func"
    end

    test "sanitizes complex metadata values" do
      doc_list = [
        {TestModule, "Module doc", %{},
         [
           {{:function, :func, 1}, %{"en" => "Doc"},
            %{
              atom_key: :atom_value,
              list_key: [1, 2, 3],
              tuple_key: {:ok, "value"},
              nested_map: %{inner: :value},
              charlist: ~c"charlist"
            }}
         ]}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert [func] = module_doc["functions"]

      # Verify sanitization
      metadata = func["metadata"]
      assert metadata["atom_key"] == "atom_value"
      assert metadata["list_key"] == [1, 2, 3]
      assert metadata["tuple_key"] == ["ok", "value"]
      assert metadata["nested_map"]["inner"] == "value"
      assert metadata["charlist"] == "charlist"
    end

    test "handles empty function list" do
      doc_list = [
        {TestModule, "Module with no functions", %{}, []}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert module_doc["functions"] == []
    end

    test "formats multiple modules" do
      doc_list = [
        {Module1, "First module", %{}, []},
        {Module2, "Second module", %{}, []}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["module"] == "Module1"
      assert Enum.at(decoded, 1)["module"] == "Module2"
    end

    test "produces pretty-printed JSON" do
      doc_list = [
        {TestModule, "Module doc", %{}, []}
      ]

      result = DocoutFormatter.format(doc_list)

      # Check that the output is pretty-printed (contains newlines)
      assert String.contains?(result, "\n")
      assert String.contains?(result, "  ")
    end

    test "handles docs_v1 format for moduledoc" do
      doc_list = [
        {TestModule,
         {:docs_v1, 1, :elixir, "text/markdown", %{"en" => "Module doc"}, %{},
          []}, %{}, []}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert module_doc["moduledoc"] == "Module doc"
    end

    test "sanitizes all primitive types correctly" do
      doc_list = [
        {TestModule, "Module doc", %{},
         [
           {{:function, :func, 1}, %{"en" => "Doc"},
            %{
              string: "text",
              integer: 42,
              float: 3.14,
              boolean: true,
              atom: :test,
              nil_value: nil
            }}
         ]}
      ]

      result = DocoutFormatter.format(doc_list)
      decoded = Jason.decode!(result)

      assert [module_doc] = decoded
      assert [func] = module_doc["functions"]

      metadata = func["metadata"]
      assert metadata["string"] == "text"
      assert metadata["integer"] == 42
      assert metadata["float"] == 3.14
      assert metadata["boolean"] == true
      assert metadata["atom"] == "test"
      # Note: nil values may be excluded from JSON encoding
      # This is expected behavior for JSON serialization
    end
  end
end
