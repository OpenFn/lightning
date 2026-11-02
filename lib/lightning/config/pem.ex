defmodule Lightning.Config.PEM do
  @moduledoc """
  Reads a PEM block from an environment variable's value.

  The value is either the PEM text, however its line breaks arrived, or that
  text base64-encoded with any wrapping and padding. Line breaks may arrive as
  newlines, CRLF, indented lines, spaces, or a literal `\\n`. A backslash never
  appears in a PEM, so reading a literal `\\n` as a line break can't misread a
  key.
  """

  @type error ::
          :empty
          | :quoted
          | :not_pem
          | {:truncated, label :: String.t()}
          | :damaged
          | :several_blocks
          | :unknown_label

  # An error names a label only from this list. A BEGIN line that lost its
  # closing dashes runs on into the body when the value is on one line, so
  # whatever follows "-----BEGIN " can be the key itself.
  @labels [
    "PUBLIC KEY",
    "RSA PUBLIC KEY",
    "PRIVATE KEY",
    "RSA PRIVATE KEY",
    "EC PRIVATE KEY",
    "ENCRYPTED PRIVATE KEY",
    "CERTIFICATE"
  ]

  @begin "-----BEGIN "
  @labelled ~r/\A(#{Enum.join(@labels, "|")})-----(.*)\z/s

  @doc """
  Returns the PEM block in `value` as canonical PEM text: the BEGIN line, the
  body in 64-column lines and the END line, each ending in a newline.

  Text before the BEGIN line and after the END line is ignored, as OpenSSL
  ignores it. The error never holds any part of `value`:

    * `:empty`: nothing but whitespace.
    * `:quoted`: base64 wrapped in quote characters.
    * `:not_pem`: neither PEM text nor base64 of PEM text.
    * `{:truncated, label}`: a BEGIN line with no matching END line.
    * `:damaged`: the body between BEGIN and END is not base64.
    * `:several_blocks`: more than one BEGIN line.
    * `:unknown_label`: a BEGIN line whose label is not one of
      #{Enum.map_join(@labels, ", ", &"`#{&1}`")}, or that doesn't end in five
      dashes.
  """
  @spec from_env(String.t()) :: {:ok, String.t()} | {:error, error()}
  def from_env(value) do
    cond do
      String.trim(value) == "" -> {:error, :empty}
      String.contains?(value, @begin) -> read_pem(value)
      true -> read_base64(value)
    end
  end

  defp read_base64(value) do
    if quoted?(String.trim(value)) do
      {:error, :quoted}
    else
      case Base.decode64(value, ignore: :whitespace, padding: false) do
        {:ok, decoded} ->
          read_pem(decoded)

        :error ->
          {:error, :not_pem}
      end
    end
  end

  defp quoted?(<<quote, _::binary>> = value) when quote in [?", ?'],
    do: byte_size(value) > 1 and String.ends_with?(value, <<quote>>)

  defp quoted?(_value), do: false

  defp read_pem(text) do
    case :binary.split(text, @begin, [:global]) do
      [_no_begin] -> {:error, :not_pem}
      [_before_begin, block] -> read_block(block)
      [_, _, _ | _] -> {:error, :several_blocks}
    end
  end

  defp read_block(block) do
    case Regex.run(@labelled, block, capture: :all_but_first) do
      [label, rest] ->
        with {:ok, body} <- body_before_end(rest, label),
             {:ok, der} <- decode_body(body) do
          {:ok, encode(label, der)}
        end

      nil ->
        {:error, :unknown_label}
    end
  end

  defp body_before_end(rest, label) do
    case :binary.split(rest, "-----END #{label}-----") do
      [body, _after_end] -> {:ok, body}
      [_no_end] -> {:error, {:truncated, label}}
    end
  end

  defp decode_body(body) do
    case body
         |> String.replace(~r/\s|\\[nr]/, "")
         |> Base.decode64(padding: false) do
      {:ok, der} -> {:ok, der}
      :error -> {:error, :damaged}
    end
  end

  defp encode(label, der) do
    lines =
      ~r/.{1,64}/
      |> Regex.scan(Base.encode64(der))
      |> Enum.map_join(fn [line] -> line <> "\n" end)

    "-----BEGIN #{label}-----\n" <> lines <> "-----END #{label}-----\n"
  end
end
