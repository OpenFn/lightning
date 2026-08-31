defmodule Lightning.ExportUtils.Scalar do
  @moduledoc """
  Encodes single strings as YAML scalars for project export.

  `Lightning.ExportUtils` builds the project spec by concatenating strings, so
  every name, label and identifier has to be quoted and escaped here.

  Output has to stay byte-identical for anything already emitted correctly:
  customers keep their project spec in git, so a change in quoting style is a
  diff in every synced repo. That is why the bare and single-quoted shapes
  below are the historic ones rather than what a general purpose YAML writer
  would pick.
  """

  # The historic bare shapes. Anchored with \A and \z rather than ^ and $ so a
  # trailing newline cannot slip through the way it used to.
  @bare_value ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.> ]*[a-zA-Z0-9]\z/

  @bare_key ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.>]*[a-zA-Z0-9]\z/

  # The spellings that do not survive a round trip as the string we wrote.
  # Measured against yamerl and yaml@2.7.1, in both key and value position;
  # the corpus is in scalar_test.exs. Deliberately narrower than YAML 1.1:
  # `on`/`off` and `2026-08-27` are left bare because neither parser resolves
  # them and both were legal job names, so quoting would churn synced repos.
  # Keys matter as much as values: yamerl reads a bare `42` key as an integer.
  @typed_words ~w(true True TRUE false False FALSE null Null NULL ~)

  # Decimal, hex and octal. The signed and digitless forms (`-0x1f`, `0x`) are
  # here because yamerl resolves them even though the npm parser does not; an
  # uppercase `0X`/`0O` prefix is a string in both and is deliberately absent.
  @typed_integer ~r/\A[-+]?(0x[0-9a-fA-F]*|0o[0-7]*|[0-9]+)\z/

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

  Used for adaptor and cron expression, which have always been quoted. A cron
  with no wildcard, such as `5 4 1 1 1`, is bare-legal, and letting it come out
  bare would be a one-line diff in every synced repo that has one.
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

  The historic shape is kept byte for byte, including the trailing newline the
  reader adds to a body that did not have one. The `cond` below documents the
  three shapes that shape gets wrong.
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
      # both.
      leading_space?(value) and trailing_blank_content_line?(value) ->
        encode_value(value)

      true ->
        literal_block(value, indent)
    end
  end

  # The two indicators are independent and a value can need both, so they are
  # computed separately rather than chosen between. `|2+` is accepted by both
  # parsers.
  defp literal_block(value, indent) do
    keep? = keep_trailing_newlines?(value)

    body = if keep?, do: drop_last_line(value), else: value

    header = "|#{indentation_indicator(value)}#{if keep?, do: "+", else: ""}"

    header <> "\n" <> indent_lines(body, indent)
  end

  # Two or more trailing newlines clip down to one, so they need `+` to be
  # kept. So does a single one with nothing in front of it: a value of "\n" has
  # no content line, and clipping takes the newline with it and returns "".
  defp keep_trailing_newlines?(value) do
    case trailing_newlines(value) do
      0 -> false
      1 -> String.replace_trailing(value, "\n", "") == ""
      _more -> true
    end
  end

  # The 2 is the indent this module adds per level.
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

  # A leading empty line is harmless: it carries the block's own indentation,
  # which is never more than the first content line's.
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

  # A final empty line is skipped: that is the segment after the closing
  # newline, which the chomping indicator accounts for.
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
      # A key with no control characters only needs \ and " escaped, which is
      # what full escaping does anyway.
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
