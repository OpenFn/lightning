defmodule Lightning.Invocation.RequestHeaders do
  @moduledoc """
  Prepares inbound HTTP headers for storage in `dataclip.request`.

  `cookie` and `proxy-authorization` are redacted by name; neither is addressed
  to a job. `authorization` and `x-api-key` -- the two headers
  `LightningWeb.Auth` reads -- keep their value with the trigger's own auth
  secrets scrubbed out of it, so a caller's token survives but the secret
  Lightning just consumed does not. Every other header is stored verbatim.
  """

  alias Lightning.Scrubber
  alias Lightning.Workflows.WebhookAuthMethod

  @redacted "[REDACTED]"

  @redacted_by_name ~w(cookie proxy-authorization)

  @value_scrubbed ~w(authorization x-api-key)

  @doc """
  Returns the map stored as `dataclip.request["headers"]`.

  `auth_methods` must be loaded: an unloaded association raises rather than
  being read as "no secrets to scrub". Duplicate header names collapse to the
  last, as `Enum.into/2` did before this module existed.
  """
  @spec redact([{String.t(), String.t()}], [WebhookAuthMethod.t()]) :: map()
  def redact(req_headers, auth_methods)
      when is_list(req_headers) and is_list(auth_methods) do
    samples = samples_for(auth_methods)

    req_headers
    |> Enum.map(fn {name, value} ->
      case String.downcase(name) do
        downcased when downcased in @redacted_by_name ->
          {name, @redacted}

        downcased when downcased in @value_scrubbed ->
          {name, scrub_value(value, samples)}

        _other ->
          {name, value}
      end
    end)
    |> Map.new()
  end

  defp samples_for([]), do: []

  # `encode_samples/2` also covers the base64 forms, so a `Basic` credential is
  # matched as well as the raw password.
  defp samples_for(auth_methods) do
    Scrubber.encode_samples(
      Enum.flat_map(auth_methods, &WebhookAuthMethod.sensitive_values_for/1),
      Enum.flat_map(auth_methods, &WebhookAuthMethod.basic_auth_for/1)
    )
  end

  defp scrub_value(value, samples) when is_binary(value) do
    Enum.reduce(samples, value, fn sample, acc ->
      String.replace(acc, sample, @redacted)
    end)
  end

  defp scrub_value(value, _samples), do: value
end
