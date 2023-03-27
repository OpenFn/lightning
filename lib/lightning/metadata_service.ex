defmodule Lightning.MetadataService do
  @moduledoc """
  Retrieves metadata for a given credential and adaptor using the OpenFn CLI.
  """

  @adaptor_service :adaptor_service

  alias Lightning.AdaptorService
  alias Lightning.Credentials.Credential
  alias Lightning.CLI

  @doc """
  Retrieve metadata for a given adaptor and credential.

  The adaptor must be an npm specification.
  """
  @spec fetch(adaptor :: String.t(), Credential.t()) :: map()
  def fetch(adaptor, %Credential{body: credential_body}) do
    with {:ok, adaptor_path} <- get_adaptor_path(adaptor),
         res <- CLI.metadata(credential_body, adaptor_path),
         {:ok, path} <- get_output_path(res) do
      path
      |> File.read()
      |> case do
        {:ok, body} -> Jason.decode!(body)
        e -> e
      end
    end
  end

  defp get_adaptor_path(adaptor) do
    case AdaptorService.find_adaptor(@adaptor_service, adaptor) do
      nil -> {:error, :no_matching_adaptor}
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
      {:error, :no_metadata_result}
    end
  end
end
