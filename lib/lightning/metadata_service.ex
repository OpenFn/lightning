defmodule Lightning.MetadataService do
  @moduledoc """
  Retrieves metadata for a given credential and adaptor using the OpenFn CLI.
  """

  defmodule Error do
    @type t :: %__MODULE__{type: atom, detail: any}

    defexception [:type, :detail]

    def message(%{type: :no_matching_adaptor}) do
      "blerg #{:no_matching_adaptor}"
    end

    def message(%{type: :no_metadata_result}) do
      "blerg #{:no_metadata_result}"
    end

    def message(%{type: :invalid_json}) do
      "blerg #{:invalid_json}"
    end
  end

  @adaptor_service :adaptor_service

  alias Lightning.AdaptorService
  alias Lightning.Credentials.Credential
  alias Lightning.CLI

  @doc """
  Retrieve metadata for a given adaptor and credential.

  The adaptor must be an npm specification.
  """
  @spec fetch(adaptor :: String.t(), Credential.t()) ::
          {:ok, %{optional(binary) => binary}} | {:error, Error.t() | }
  def fetch(adaptor, %Credential{body: credential_body}) do
    with {:ok, adaptor_path} <- get_adaptor_path(adaptor),
         res <- CLI.metadata(credential_body, adaptor_path),
         {:ok, path} <- get_output_path(res) do
      path
      |> File.read()
      |> case do
        {:ok, body} -> parse_body(body)
        e -> e
      end
    end
  end

  defp parse_body(body) do
    Jason.decode(body)
    |> case do
      {:error, e} -> {:error, %Error{type: :invalid_json, detail: e}}
      res -> res
    end
  end

  defp get_adaptor_path(adaptor) do
    case AdaptorService.find_adaptor(@adaptor_service, adaptor) do
      nil -> {:error, %Error{type: :no_matching_adaptor}}
      %{path: path} -> {:ok, path}
    end
  end

  defp get_output_path(result) do
    path =
      result
      |> CLI.Result.get_messages()
      |> List.first()

    if path do
      {:ok, path}
    else
      {:error, %Error{type: :no_metadata_result}}
    end
  end
end
