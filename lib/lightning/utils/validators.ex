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

  # A name may contain anything except a control character. Concretely: C0
  # (U+0000-U+001F), DEL (U+007F), C1 (U+0080-U+009F, which is where NEL lives),
  # the two line separators U+2028 and U+2029, and the two non-characters
  # U+FFFE and U+FFFF. Everything else is allowed, including letters and marks
  # from any script, punctuation, symbols, emoji, quotes and apostrophes.
  #
  # U+2028 and U+2029 are here because YAML 1.1 counts them as line breaks
  # alongside LF, CR and NEL. A name holding one produces a spec that libyaml
  # and PyYAML reject outright while the npm parser reads it, and a writer that
  # emits it as a real break splits the name across lines, so the key and the
  # name field stop agreeing.
  #
  # Control characters are out because job names are written into the
  # `workflow_snapshots.jobs` jsonb column, and Postgres refuses a NUL inside
  # jsonb, so a name carrying one crashes the snapshot insert (#4893). We
  # reject rather than strip: silently rewriting what someone typed is worse
  # than telling them.
  #
  # `Lightning.LogMessage` keeps a narrower regex that it strips rather than
  # rejects. That is deliberate for log lines, which legitimately hold tabs and
  # newlines, so the two must not be merged.
  @control_chars_regex ~r/[\x00-\x1F\x7F\x{0080}-\x{009F}\x{2028}\x{2029}\x{FFFE}\x{FFFF}]/u

  @control_chars_message "can't contain control characters"

  # Characters that take no space and draw nothing. A name made only of these
  # passes every other check, renders as an empty label everywhere in the UI,
  # and becomes an invisible key in the project spec. `String.trim/1` already
  # empties a name made only of spaces, tabs, newlines, NBSP or U+3000, so this
  # closes the same hole for the characters trim does not know about.
  #
  # A property test rather than a list. The list this replaced held 30
  # codepoints and let 406 through, and the arbitrary part was that it took
  # U+FE0E and U+FE0F but not U+FE00 to U+FE0D from the same block. `\p{Cf}` is
  # the bulk of it; the explicit ranges are the codepoints that are
  # Default_Ignorable_Code_Point without being format characters -- the
  # combining grapheme joiner, the Hangul and Khmer fillers, the variation
  # selectors and their supplement, the tag block -- plus U+2800, the Braille
  # blank, which is not default-ignorable but still draws nothing. The Egyptian
  # hieroglyph controls are spelled out because PCRE's tables here predate
  # their move into Cf.
  #
  # Only a name that is *nothing but* these is refused. A name that merely
  # contains one is fine: a joiner is how an emoji sequence, a Devanagari
  # conjunct and an Arabic ligature are written.
  # Written on one line on purpose: PCRE's /x does not ignore whitespace inside
  # a character class, so laying this out over several lines silently put a
  # literal space and newline into the set.
  @invisible_regex ~r/\A[\p{Cf}\x{034F}\x{115F}\x{1160}\x{17B4}\x{17B5}\x{180B}-\x{180F}\x{2065}\x{2800}\x{3164}\x{FE00}-\x{FE0F}\x{FFA0}\x{FFF0}-\x{FFF8}\x{13430}-\x{1343F}\x{E0000}-\x{E0FFF}]+\z/u

  # The width of jobs.name and workflows.name, counted the way Postgres counts
  # a varchar: in codepoints.
  @column_limit 255

  @doc """
  Normalises a name field and rejects any control character in it.

  The value is normalised to NFC and trimmed before anything else runs, so a
  later `validate_required/3` or `validate_length/3` in the same changeset sees
  the value that will actually be stored. Call this straight after `cast/3`.

  A name may hold any other codepoint. See `@control_chars_regex` above for why
  control characters are the one exception, and `assets/js/utils/nameValidation.ts`
  for the client-side copy of the same rule.
  """
  @spec validate_name(Ecto.Changeset.t(), atom(), String.t()) ::
          Ecto.Changeset.t()
  def validate_name(changeset, field, message \\ @control_chars_message) do
    changeset
    |> update_change(field, &normalize_name/1)
    |> validate_change(field, fn ^field, value ->
      if valid_name?(value), do: [], else: [{field, message}]
    end)
    |> validate_change(field, fn ^field, value ->
      if invisible_only?(value), do: [{field, "can't be blank"}], else: []
    end)
  end

  @doc """
  The set of codepoints a name may not contain. Exposed for tests and for
  anything that needs to check a string without building a changeset.
  """
  @spec control_chars_regex() :: Regex.t()
  def control_chars_regex, do: @control_chars_regex

  @doc """
  True when a string is made up entirely of characters that draw nothing.

  Exposed so the fixture that keeps the client's copy of this rule in step can
  be generated from it. See `assets/js/utils/nameValidation.ts`.
  """
  @spec invisible_only?(binary()) :: boolean()
  def invisible_only?(value) when is_binary(value) do
    value != "" and String.valid?(value) and
      Regex.match?(@invisible_regex, value)
  end

  def invisible_only?(_value), do: false

  @doc """
  Rejects a NUL in a field that ends up inside a jsonb column.

  A job body and an edge's condition expression are both copied into
  `workflow_snapshots`, and Postgres refuses a NUL anywhere inside a jsonb
  value (`22P05`). Unlike a name, these fields legitimately hold newlines and
  tabs, so only the NUL is refused rather than the whole control set.

  Malformed UTF-8 goes the same way, for the same reason it does in
  `validate_name/3`.
  """
  @spec validate_no_null_bytes(Ecto.Changeset.t(), atom(), String.t()) ::
          Ecto.Changeset.t()
  def validate_no_null_bytes(changeset, field, message) do
    validate_change(changeset, field, fn ^field, value ->
      if storable_in_jsonb?(value), do: [], else: [{field, message}]
    end)
  end

  @doc """
  Rejects a NUL anywhere inside a map field that ends up in a jsonb column.

  `workflow.positions` and a trigger's `kafka_configuration` are maps written
  straight into `workflow_snapshots`, and Postgres refuses a NUL anywhere
  inside a jsonb value, keys included. Walks the whole structure rather than
  checking the top level, because a NUL in a key is just as fatal as one in a
  value.
  """
  @spec validate_no_null_bytes_deep(Ecto.Changeset.t(), atom(), String.t()) ::
          Ecto.Changeset.t()
  def validate_no_null_bytes_deep(changeset, field, message) do
    validate_change(changeset, field, fn ^field, value ->
      if jsonb_safe?(value), do: [], else: [{field, message}]
    end)
  end

  @doc """
  Rejects a name that will not fit the column it is stored in.

  Both `jobs.name` and `workflows.name` are `varchar(255)`, and Postgres counts
  those 255 in codepoints. The product caps above this one count graphemes, so
  the two disagree on anything built from multi-codepoint clusters: 100 ZWJ
  family emoji are 100 graphemes and 700 codepoints, which passes a 100
  grapheme cap and then raises `22001` on insert. Names were ASCII-only until
  #4577, which is why this never came up before.

  Skipped when the field already has an error, so a plainly over-long name gets
  the product cap's message and this one stays quiet.

  `width` defaults to 255, which is what every name column in this schema is.
  Pass it explicitly for a narrower one, such as `credentials.schema`.

  The message callers pass should not quote a number. From where the user sits
  the limit is the product cap, and being told "at most 255" after being told
  "at most 100" reads as a bug even though both are true. Say it is too long
  and ask for a shorter one.
  """
  @spec validate_name_fits_column(
          Ecto.Changeset.t(),
          atom(),
          String.t(),
          pos_integer()
        ) :: Ecto.Changeset.t()
  def validate_name_fits_column(
        changeset,
        field,
        message,
        width \\ @column_limit
      ) do
    if Keyword.has_key?(changeset.errors, field) do
      changeset
    else
      validate_length(changeset, field,
        max: width,
        count: :codepoints,
        message: message
      )
    end
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

  defp normalize_name(value) when is_binary(value) do
    case :unicode.characters_to_nfc_binary(value) do
      normalized when is_binary(normalized) -> String.trim(normalized)
      _malformed -> value
    end
  end

  defp normalize_name(value), do: value

  # Malformed UTF-8 is rejected here too. Postgres refuses it on the way in, so
  # letting it through would be a 500 rather than a changeset error, and the
  # regex cannot be run against it in the first place.
  defp valid_name?(value) when is_binary(value) do
    String.valid?(value) and not Regex.match?(@control_chars_regex, value)
  end

  defp valid_name?(_value), do: true

  defp storable_in_jsonb?(value) when is_binary(value) do
    String.valid?(value) and not String.contains?(value, <<0>>)
  end

  defp storable_in_jsonb?(_value), do: true

  defp jsonb_safe?(value) when is_binary(value), do: storable_in_jsonb?(value)

  defp jsonb_safe?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {k, v} -> jsonb_safe?(k) and jsonb_safe?(v) end)
  end

  defp jsonb_safe?(value) when is_list(value),
    do: Enum.all?(value, &jsonb_safe?/1)

  defp jsonb_safe?(value) when is_atom(value),
    do: storable_in_jsonb?(Atom.to_string(value))

  defp jsonb_safe?(_value), do: true

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
