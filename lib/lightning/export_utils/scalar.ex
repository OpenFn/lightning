defmodule Lightning.ExportUtils.Scalar do
  @moduledoc """
  Encodes single strings as YAML scalars for project export.

  `Lightning.ExportUtils` builds the project spec by concatenating strings, so
  every name, label and identifier that ends up in the spec has to be quoted and
  escaped here. Two rules drive the whole module.

  The first is that output has to stay byte-identical for anything we already
  emit correctly. Customers keep their project spec in git, so a change in
  quoting style would show up as a diff in every synced repo. That is why the
  bare and single-quoted shapes below are the historic ones rather than what a
  general purpose YAML writer would pick.

  The second is that anything we could not emit correctly has to change. A name
  like `MailChimp June'24` used to come out as `'MailChimp June'24'`, which no
  parser reads back (issue #2808). A name of `null` or `42` came out bare and
  read back as nil or a number, and as a key `007` came back as `7`. A name
  with a newline in it injected sibling keys into the spec.

  Those two rules pull against each other, so the set of strings we refuse to
  leave bare is measured rather than assumed. It is exactly what yamerl or the
  npm `yaml` parser resolves to something other than the string we wrote. A
  name of `off` or `2026-08-27` is left bare, because both parsers hand it
  back as the string it was.
  """

  # The historic bare shapes. Anchored with \A and \z rather than ^ and $ so a
  # trailing newline cannot slip through the way it used to.
  #
  # value: starts alphanumeric, then alphanumeric or _ - @ . > or space, ends
  # alphanumeric.
  @bare_value ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.> ]*[a-zA-Z0-9]\z/

  # key: the same, without the space.
  @bare_key ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.>]*[a-zA-Z0-9]\z/

  # The spellings that do not survive a round trip as the string we wrote.
  #
  # Measured against both parsers this project actually ships against, in both
  # positions, rather than taken from the YAML 1.1 spec: yamerl (through
  # YamlElixir, which reads specs here and in the CLI) and yaml@2.7.1 (the
  # browser). The corpus and the result for each parser is in scalar_test.exs,
  # so this set cannot be widened again without evidence.
  #
  # Two things the spec would have had us quote and neither parser resolves:
  # the `y n yes no on off` words in every casing, and timestamps like
  # `2026-08-27`. Both were legal job names under the old charset rule, so
  # quoting them would have put a diff into every synced repo holding one.
  #
  # Keys matter as much as values here. yamerl hands back a bare `42` key as
  # the integer 42 and the npm parser turns `007` into the key `7` and `1e3`
  # into `1000`, either of which breaks the invariant that a job's key is its
  # hyphenated name.
  @typed_words ~w(true True TRUE false False FALSE null Null NULL ~)

  # Decimal, hex and octal. The signed and digitless forms (`-0x1f`, `0x`) are
  # here because yamerl resolves them even though the npm parser does not; an
  # uppercase `0X`/`0O` prefix is a string in both and is deliberately absent.
  @typed_integer ~r/\A[-+]?(0x[0-9a-fA-F]*|0o[0-7]*|[0-9]+)\z/

  # A point with a digit on one side or the other, an exponent without a point,
  # and the infinity and not-a-number spellings.
  @typed_float ~r/
    \A
    (
      [-+]?\.(inf|Inf|INF)
    | \.(nan|NaN|NAN)
    | [-+]?([0-9]+\.[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?
    | [-+]?[0-9]+[eE][-+]?[0-9]+
    )
    \z
  /x

  @doc """
  Encodes a string as a YAML scalar suitable for the right hand side of a
  mapping entry or for a sequence item.
  """
  @spec encode_value(binary()) :: binary()
  def encode_value(value) when is_binary(value) do
    if Regex.match?(@bare_value, value) and not typed?(value) do
      value
    else
      encode_quoted_value(value)
    end
  end

  @doc """
  Encodes a string as a YAML scalar that is always quoted, never left bare.

  Two fields are written this way because they always have been: an adaptor and
  a cron expression. Almost every real value of either fails the bare-scalar
  regex anyway, but not all of them. A cron with no wildcard in it, such as
  `5 4 1 1 1`, is bare-legal, and letting it come out bare would put a
  one-line diff into every synced project repo that has a cron of that shape
  for no gain. Byte-identity with what we already emit is worth more than the
  handful of quotes it costs.

  Escaping is the same as `encode_value/1`: the point of routing these two
  through here at all is that they used to be concatenated into the spec raw.
  """
  @spec encode_quoted_value(binary()) :: binary()
  def encode_quoted_value(value) when is_binary(value) do
    if single_quotable?(value) do
      single_quote(value)
    else
      double_quote(value)
    end
  end

  @doc """
  Encodes a multi-line value as a literal block scalar, header and indented
  body together, ready to follow `"key: "`.

  `body`, `description` and `condition_expression` carry the most user text in
  the spec and were the last three fields written by raw concatenation. Three
  shapes broke them (issue #2966):

    * a first line starting with a space. The reader takes that space as part
      of the block's indentation, and every following line then looks
      under-indented. yamerl and the npm parser both silently drop the leading
      spaces rather than failing.
    * a carriage return. YAML counts CR as a line break, so `a\r\nb` reads back
      as `a\nb`, and a lone CR makes a document yamerl refuses outright.
    * two or more trailing newlines, which clip down to one.

  The historic shape is kept byte for byte for everything else, including the
  single trailing newline the reader adds to a body that did not have one.
  Changing that would rewrite the body of every job in every synced repo.
  """
  @spec encode_block(binary(), binary()) :: binary()
  def encode_block(value, indent) when is_binary(value) and is_binary(indent) do
    # No block scalar can carry a CR: YAML counts it as a line break, so the
    # reader hands back an LF, and a lone CR is a document yamerl refuses. The
    # quoted form escapes it.
    cond do
      String.contains?(value, "\r") ->
        encode_value(value)

      # A value that is nothing but spaces has no content line for the reader
      # to measure the block against, and the two parsers disagree about what
      # comes back: yamerl keeps them, the npm parser returns "". Narrow to
      # spaces on purpose. A value of "\t" or a non-breaking space has a
      # content line as far as the reader is concerned and keeps its historic
      # shape, as does the empty string.
      spaces_only?(value) ->
        encode_value(value)

      # `|2` plus a trailing whitespace-only content line is the one repaired
      # shape the two parsers disagree on: yamerl keeps that line, the npm
      # parser strips it as trailing whitespace. Quoting is unambiguous in
      # both. Only ever reached for a value the historic shape already got
      # wrong, so no correct output changes.
      leading_space?(value) and trailing_blank_content_line?(value) ->
        encode_value(value)

      true ->
        literal_block(value, indent)
    end
  end

  # The two indicators are independent and a value can need both, so they are
  # computed separately rather than chosen between. A body that starts with an
  # indented line and ends with a blank one is ordinary pasted code, and
  # picking the indentation branch alone silently dropped its trailing
  # newlines. `|2+` is accepted by both parsers.
  defp literal_block(value, indent) do
    keep? = keep_trailing_newlines?(value)

    body = if keep?, do: drop_last_line(value), else: value

    header = "|#{indentation_indicator(value)}#{if keep?, do: "+", else: ""}"

    header <> "\n" <> indent_lines(body, indent)
  end

  # Two or more trailing newlines clip down to one, so they need `+` to be
  # kept. So does a single one with nothing in front of it: a value of "\n" has
  # no content line, and clipping takes the newline with it and returns "".
  # Everything else keeps the shape this module has always written, byte for
  # byte, including the single trailing newline the reader adds to a value that
  # did not have one. Correcting that would rewrite the body of every job in
  # every synced repo for no gain.
  defp keep_trailing_newlines?(value) do
    case trailing_newlines(value) do
      0 -> false
      1 -> String.replace_trailing(value, "\n", "") == ""
      _more -> true
    end
  end

  # The reader takes the first content line's own leading space as part of the
  # block's indentation and silently eats it. An explicit indicator says where
  # the block really starts. The 2 is the indent this module adds per level.
  defp indentation_indicator(value) do
    if leading_space?(value), do: "2", else: ""
  end

  defp indent_lines(value, indent) do
    value
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> "#{indent}  #{line}" end)
  end

  defp drop_last_line(value) do
    value |> String.split("\n") |> Enum.drop(-1) |> Enum.join("\n")
  end

  # The first line with anything on it. A leading empty line is harmless: it
  # carries the block's own indentation, which is never more than the first
  # content line's.
  defp leading_space?(value) do
    value
    |> String.split("\n")
    |> Enum.find(&(&1 != ""))
    |> case do
      nil -> false
      line -> String.starts_with?(line, " ")
    end
  end

  defp spaces_only?(value) do
    value != "" and String.trim(value, " ") == ""
  end

  # The last line with anything on it is whitespace but not empty. A final
  # empty line is skipped: that is the segment after the closing newline, which
  # the chomping indicator accounts for.
  defp trailing_blank_content_line?(value) do
    value
    |> String.split("\n")
    |> Enum.reverse()
    |> Enum.find(&(&1 != ""))
    |> case do
      nil -> false
      line -> String.trim(line) == ""
    end
  end

  defp trailing_newlines(value) do
    byte_size(value) - byte_size(String.replace_trailing(value, "\n", ""))
  end

  @doc """
  Encodes a string as a YAML mapping key.

  Keys use double quotes rather than single quotes, which is the style the
  export has always used for them.
  """
  @spec encode_key(binary()) :: binary()
  def encode_key(key) when is_binary(key) do
    if Regex.match?(@bare_key, key) and not typed?(key) do
      key
    else
      # Both quoted cases collapse into one here. A key with no control
      # characters only needs \ and " escaped, and that is exactly what full
      # escaping does when there is nothing else to escape.
      double_quote(key)
    end
  end

  # A string YAML would resolve to something other than a string if we left it
  # bare.
  defp typed?(""), do: true

  defp typed?(string) do
    string in @typed_words or
      Regex.match?(@typed_integer, string) or
      Regex.match?(@typed_float, string)
  end

  # A single-quoted scalar can hold anything printable on one line. It cannot
  # hold a line break or a control character, because single quotes have no
  # escape sequence other than the doubled quote. U+2028 and U+2029 are in here
  # because YAML 1.1 counts them as line breaks alongside LF, CR and NEL: left
  # raw, libyaml and PyYAML reject the document while the npm parser accepts
  # it. The last two are the non-characters YAML also excludes from its
  # printable set.
  @unprintable ~r/[\x00-\x1F\x7F\x{0080}-\x{009F}\x{2028}\x{2029}\x{FFFE}\x{FFFF}]/u

  defp single_quotable?(string) do
    not String.match?(string, @unprintable)
  end

  defp single_quote(string) do
    ~s('#{String.replace(string, "'", "''")}')
  end

  defp double_quote(string) do
    escaped =
      string
      |> String.to_charlist()
      |> Enum.map_join(&escape_char/1)

    ~s("#{escaped}")
  end

  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?"), do: "\\\""
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(?\t), do: "\\t"
  defp escape_char(0), do: "\\0"

  defp escape_char(codepoint)
       when codepoint in 0..0x1F or codepoint == 0x7F or
              codepoint in 0x80..0x9F or codepoint in 0x2028..0x2029 or
              codepoint in 0xFFFE..0xFFFF do
    hex_escape(codepoint)
  end

  defp escape_char(codepoint), do: <<codepoint::utf8>>

  defp hex_escape(codepoint) when codepoint <= 0xFF do
    "\\x" <> hex(codepoint, 2)
  end

  defp hex_escape(codepoint) when codepoint <= 0xFFFF do
    "\\u" <> hex(codepoint, 4)
  end

  defp hex(codepoint, width) do
    codepoint
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(width, "0")
  end
end
