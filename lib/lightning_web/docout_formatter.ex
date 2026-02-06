defmodule LightningWeb.DocoutFormatter do
  @moduledoc """
  Docout formatter that extracts module and function docs to JSON.

  Processes documentation from modules tagged with `@moduledoc docout: true`
  and converts them into a structured JSON format suitable for API
  documentation generation.

  ## Output Format

  The formatter generates JSON with the following structure:

      [
        {
          "module": "Elixir.MyModule",
          "moduledoc": "Module documentation string",
          "functions": [
            {
              "name": "my_function",
              "arity": 2,
              "doc": "Function documentation",
              "metadata": {}
            }
          ]
        }
      ]

  ## Usage

  This formatter is automatically invoked by the Docout library when
  running documentation generation tasks:

      mix docs.generate

  The output is written to `priv/static/docs.json`.
  """

  use Docout, output_path: "priv/static/docs.json"

  @type doc_entry :: {module(), moduledoc(), metadata(), functions()}
  @type moduledoc :: map() | binary() | :none | :hidden | nil
  @type metadata :: map()
  @type functions :: [function_entry()]
  @type function_entry ::
          {{:function, atom(), non_neg_integer()}, doc_content(), metadata()}
  @type doc_content :: map() | binary() | :none | :hidden | nil

  @doc """
  Formats the documentation list into JSON.

  Takes a list of documentation entries from Docout and converts them
  into a pretty-printed JSON string.

  ## Parameters

    - doc_list: List of documentation tuples from Docout

  ## Returns

    Pretty-printed JSON string of all documentation

  ## Examples

      iex> format([{MyModule, %{}, %{}, []}])
      ~s([{\\n  "module": "Elixir.MyModule",\\n  ...}])

  """
  @spec format([doc_entry()]) :: String.t()
  def format(doc_list) do
    doc_list
    |> Enum.map(&format_module/1)
    |> Jason.encode!(pretty: true)
  end

  # Formats a module documentation tuple into a structured map.
  # Structure: {module, moduledoc_map, metadata_map, function_list}
  @spec format_module(doc_entry()) :: map()
  defp format_module({module, moduledoc, _metadata, functions}) do
    %{
      module: inspect(module),
      moduledoc: extract_moduledoc(moduledoc),
      functions:
        functions
        |> Enum.map(&format_function/1)
        |> Enum.reject(&is_nil/1)
    }
  end

  # Formats a function documentation entry into a map.
  # Returns nil for hidden functions or non-function entries.
  @spec format_function(function_entry() | any()) :: map() | nil
  defp format_function({{:function, _name, _arity}, :hidden, _metadata}) do
    nil
  end

  defp format_function({{:function, name, arity}, doc, metadata}) do
    %{
      name: to_string(name),
      arity: arity,
      doc: extract_doc(doc),
      metadata: sanitize_metadata(metadata || %{})
    }
  end

  # Skip non-function entries (like :macro, :type, etc)
  defp format_function(_), do: nil

  # Converts metadata to JSON-safe format
  @spec sanitize_metadata(map() | any()) :: map()
  defp sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {key, value} -> {key, sanitize_value(value)} end)
    |> Enum.into(%{})
  end

  defp sanitize_metadata(_), do: %{}

  # Converts various Elixir types to JSON-safe values
  @spec sanitize_value(any()) :: any()
  defp sanitize_value(value) when is_binary(value), do: value
  defp sanitize_value(value) when is_number(value), do: value
  defp sanitize_value(value) when is_boolean(value), do: value
  defp sanitize_value(value) when is_atom(value), do: to_string(value)

  defp sanitize_value(value) when is_list(value) do
    # Check if it's a charlist or regular list
    if charlist?(value) do
      to_string(value)
    else
      Enum.map(value, &sanitize_value/1)
    end
  end

  defp sanitize_value(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&sanitize_value/1)
  end

  defp sanitize_value(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} ->
      {sanitize_value(k), sanitize_value(v)}
    end)
    |> Enum.into(%{})
  end

  defp sanitize_value(_), do: nil

  # Checks if a list is a charlist (printable ASCII)
  @spec charlist?(list()) :: boolean()
  defp charlist?(value) do
    Enum.all?(value, &is_integer/1) and List.ascii_printable?(value)
  end

  # Extracts moduledoc content from various formats
  @spec extract_moduledoc(moduledoc()) :: String.t() | nil
  defp extract_moduledoc({:docs_v1, _, _, _, %{"en" => doc}, _, _}) do
    doc
  end

  defp extract_moduledoc(%{"en" => doc}), do: doc
  defp extract_moduledoc(doc) when is_binary(doc), do: doc
  defp extract_moduledoc(nil), do: nil
  defp extract_moduledoc(:none), do: nil
  defp extract_moduledoc(:hidden), do: nil
  defp extract_moduledoc(_), do: nil

  # Extracts function doc content from various formats
  @spec extract_doc(doc_content()) :: String.t() | nil
  defp extract_doc(%{"en" => doc}), do: doc
  defp extract_doc(doc) when is_binary(doc), do: doc
  defp extract_doc(nil), do: nil
  defp extract_doc(:none), do: nil
  defp extract_doc(:hidden), do: nil
  defp extract_doc(_), do: nil
end
