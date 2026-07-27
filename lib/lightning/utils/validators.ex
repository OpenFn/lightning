defmodule Lightning.Validators do
  @moduledoc """
  Extra validators for Ecto.Changeset.
  """

  import Ecto.Changeset

  # Matches z.regexes.email from Zod v4 (v4.0.17) — keeps validation consistent
  # with the marketing site. Update if the Zod dependency is upgraded.
  @email_format_regex ~r/^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$/

  @doc """
  Validates that an email field contains a properly formatted email address.

  Applies: required check, format regex, max 160 chars, lowercases the value.
  This is a pure format check — no database lookup. Use `User.validate_email/1`
  when you also need to verify the email is unique in the users table.
  """
  @spec validate_email_format(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_email_format(changeset, field \\ :email) do
    changeset
    |> validate_required(field, message: "can't be blank")
    |> validate_format(field, @email_format_regex,
      message: "must be a valid email address"
    )
    |> validate_length(field, max: 160)
    |> update_change(field, &String.downcase/1)
  end

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
  Returns `true` when `value` is a well-formed UUID that will dump cleanly to a
  `:binary_id` on insert/update.

  Uses `Ecto.UUID.dump/1` (not `cast/1`): `dump` rejects raw 16-byte binaries and
  unsubstituted import placeholders that `cast` would accept, matching what the
  database actually enforces. `nil` is not a valid UUID.

  This is the single source of truth for the "dumpable UUID" check — both
  `validate_uuid/2` and schema-level guards (e.g. `Workflows.Job`) build on it so
  they cannot drift apart.
  """
  @spec valid_uuid?(term()) :: boolean()
  def valid_uuid?(value), do: match?({:ok, _}, Ecto.UUID.dump(value))

  @doc """
  Validates that the given field(s) contain a well-formed UUID.

  `:binary_id` fields are not format-checked by `cast/3` — a malformed value
  (e.g. an unsubstituted import placeholder) passes casting and only raises
  `Ecto.ChangeError` when dumped on insert/update. This converts that into a
  changeset error instead.

  Only runs when a non-nil change is present for the field, so optional
  foreign keys left unset are unaffected.

  > **Narrowing:** uses `Ecto.UUID.dump/1`, not `cast/1`. `dump` additionally
  > rejects raw 16-byte binaries and unsubstituted placeholders that `cast`
  > accepted. Confirmed no live caller relied on the laxer behaviour (uppercase
  > canonical UUIDs still pass).

  ```
  changeset
  |> validate_uuid([:id, :workflow_id])
  ```
  """
  @spec validate_uuid(Ecto.Changeset.t(), atom() | [atom()]) ::
          Ecto.Changeset.t()
  def validate_uuid(changeset, fields) when is_list(fields) do
    Enum.reduce(fields, changeset, &validate_uuid(&2, &1))
  end

  def validate_uuid(changeset, field) when is_atom(field) do
    validate_change(changeset, field, fn _, value ->
      if valid_uuid?(value), do: [], else: [{field, "is not a valid UUID"}]
    end)
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
