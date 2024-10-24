defmodule Lightning.Validators do
  @moduledoc """
  Extra validators for Ecto.Changeset.
  """

  import Ecto.Changeset

  @doc """
  Validate that only one of the fields is set at a time.

  Example:

  ```
  changeset
  |> validate_exclusive(
    [:source_job_id, :source_trigger_id],
    "source_job_id and source_trigger_id are mutually exclusive"
  )
  ```
  """
  @spec validate_exclusive(Ecto.Changeset.t(), [atom()], String.t()) ::
          Ecto.Changeset.t()
  def validate_exclusive(changeset, fields, message) do
    fields
    |> Enum.map(&get_field(changeset, &1))
    |> Enum.reject(&is_nil/1)
    |> then(fn f ->
      if length(f) > 1 do
        error_field =
          fields
          |> Enum.map(&[&1, fetch_field(changeset, &1)])
          |> Enum.find(fn [_, {kind, _}] -> kind == :changes end)
          |> List.first()

        add_error(changeset, error_field, message)
      else
        changeset
      end
    end)
  end

  @doc """
  Validate that at least one of the fields is set.
  """
  @spec validate_one_required(Ecto.Changeset.t(), [atom()], String.t()) ::
          Ecto.Changeset.t()
  def validate_one_required(changeset, fields, message) do
    fields
    |> Enum.map(&get_field(changeset, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        add_error(changeset, fields |> List.first(), message)

      _any ->
        changeset
    end
  end

  @doc """
  Validate that an association is present

  > **NOTE**
  > This should only be used when using `put_assoc`, not `cast_assoc`.
  > `cast_assoc` provides a `required: true` option.
  > Unlike `validate_required`, this does not add the field to the `required`
  > list in the schema.
  """
  @spec validate_required_assoc(Ecto.Changeset.t(), atom(), String.t()) ::
          Ecto.Changeset.t()
  def validate_required_assoc(changeset, assoc, message \\ "is required") do
    changeset
    |> get_field(assoc)
    |> case do
      nil ->
        add_error(changeset, assoc, message)

      _any ->
        changeset
    end
  end

  @doc """
  Validates a URL in a changeset field.

  Ensures that the URL:
  - Has a valid `http` or `https` scheme.
  - Has a valid host (domain name, IPv4, or IPv6).
  - The host is not blank and does not exceed 255 characters.

  Returns a changeset error for invalid URLs.
  """
  @spec validate_url(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      with url when is_binary(url) <- value,
           {:ok, uri} <- URI.new(url) do
        cond do
          uri.scheme not in ["http", "https"] ->
            [{field, "must be either a http or https URL"}]

          is_nil(uri.host) or byte_size(uri.host) == 0 ->
            [{field, "host can't be blank"}]

          byte_size(uri.host) > 255 ->
            [{field, "host must be less than 255 characters"}]

          not valid_host?(uri.host) ->
            [{field, "host has invalid characters"}]

          true ->
            []
        end
      else
        _ -> [{field, "must be a valid URL"}]
      end
    end)
  end

  defp valid_host?(host) do
    host == "localhost" or valid_ip?(host) or
      String.match?(host, ~r/^[\da-z]([\da-z\-]*[\da-z])?(\.[\da-z]+)+$/i)
  end

  defp valid_ip?(host) do
    case :inet.parse_address(to_charlist(host)) do
      {:ok, _} -> true
      _ -> valid_ipv6?(host)
    end
  end

  defp valid_ipv6?(host) do
    case :inet.parse_ipv6_address(to_charlist(host)) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
