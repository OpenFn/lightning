defmodule Lightning.MetadataService do
  @moduledoc """
  Retrieves metadata for a given credential and adaptor using the OpenFn CLI.
  """
  alias Lightning.AdaptorService
  alias Lightning.CLI
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential

  require Logger

  defmodule Error do
    @type t :: %__MODULE__{type: String.t()}

    defexception [:type]

    @spec new(type :: String.t()) :: __MODULE__.t()
    def new(type) do
      %__MODULE__{type: type}
    end

    @spec message(__MODULE__.t()) :: String.t()
    def message(%{type: type}) do
      "Got #{type}."
    end
  end

  @adaptor_service :adaptor_service
  @cli_task_worker :cli_task_worker

  @doc """
  Retrieve metadata for a given adaptor and credential.

  The adaptor must be an npm specification.

  ## Parameters
    - `adaptor`: The adaptor npm specification (e.g., "@openfn/language-http")
    - `credential`: The credential struct
    - `environment`: The environment name (defaults to "main")

  ## Returns
    - `{:ok, metadata}` - The metadata as a map
    - `{:error, Error.t()}` - An error if metadata cannot be fetched
  """
  @spec fetch(adaptor :: String.t(), Credential.t(), environment :: String.t()) ::
          {:ok, %{optional(binary) => binary}} | {:error, Error.t()}
  def fetch(adaptor, credential, environment \\ "main") do
    Lightning.TaskWorker.start_task(@cli_task_worker, fn ->
      LightningWeb.Telemetry.with_span(
        [:lightning, :fetch_metadata],
        %{adaptor: adaptor, environment: environment},
        fn ->
          do_fetch(adaptor, credential, environment)
        end
      )
    end)
    |> case do
      {:error, e} when is_atom(e) -> {:error, Error.new(e |> to_string())}
      any -> any
    end
  end

  # false positive, adaptor is resolved by a regex and given by a install function
  # sobelow_skip ["Traversal.FileModule"]
  defp do_fetch(adaptor, credential, environment) do
    with {:ok, {adaptor, state}} <-
           assemble_args(adaptor, credential, environment),
         {:ok, adaptor_path} <- get_adaptor_path(adaptor),
         res <- CLI.metadata(state, adaptor_path),
         {:ok, path} <- get_output_path(res) do
      path
      |> File.read()
      |> case do
        {:ok, body} -> parse_body(body)
        e -> e
      end
    end
  end

  defp assemble_args(adaptor, credential, environment) do
    case {adaptor, credential} do
      {nil, _} ->
        {:error, Error.new("no_adaptor")}

      {_, %Ecto.Association.NotLoaded{}} ->
        {:error, Error.new("no_credential")}

      {_, nil} ->
        {:error, Error.new("no_credential")}

      {adaptor_path, %Credential{} = cred} ->
        case Credentials.resolve_credential_body(cred, environment) do
          {:ok, credential_body} ->
            {:ok,
             {adaptor_path,
              %{"configuration" => Lightning.RedactedMap.new(credential_body)}}}

          {:error, :environment_not_found} ->
            {:error, Error.new("environment_not_found")}

          {:error, :reauthorization_required} ->
            {:error, Error.new("reauthorization_required")}

          {:error, :temporary_failure} ->
            {:error, Error.new("temporary_oauth_failure")}

          {:error, _} ->
            {:error, Error.new("credential_resolution_failed")}
        end

      {_adaptor_path, %{}} ->
        {:error, Error.new("unsupported_credential")}
    end
  end

  defp parse_body(body) do
    Jason.decode(body)
    |> case do
      {:error, _error} -> {:error, Error.new("invalid_json")}
      res -> res
    end
  end

  defp get_adaptor_path(adaptor) do
    case AdaptorService.install(@adaptor_service, adaptor) do
      {:error, _} ->
        {:error, Error.new("no_matching_adaptor")}

      {:ok, %{path: path}} when not is_nil(path) ->
        {:ok, path}

      other ->
        Sentry.capture_message("AdaptorService.install failed",
          level: :warning,
          message: inspect(other),
          extra: %{adaptor: adaptor}
        )

        {:error, Error.new("adaptor_service_install_error")}
    end
  end

  defp get_output_path(result) do
    last_message =
      result
      |> CLI.Result.get_messages()
      |> List.last()

    cond do
      is_map(last_message) ->
        {:error, Error.new("no_metadata_result")}

      Regex.match?(~r"^[/a-zA-z0-9\-_\.]+\.json$", last_message) ->
        path = last_message
        {:ok, path}

      should_have_metadata(result) ->
        {:error, Error.new("no_metadata_result")}

      true ->
        {:error, Error.new("no_metadata_function")}
    end
  end

  defp should_have_metadata(result) do
    result
    |> Map.get(:logs, [])
    |> Enum.any?(fn log ->
      List.first(Map.get(log, "message", ""))
      |> String.contains?("Metadata function found")
    end)
  end
end
