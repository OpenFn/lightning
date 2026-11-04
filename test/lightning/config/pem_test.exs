defmodule Lightning.Config.PEMTest do
  use ExUnit.Case, async: true

  alias Lightning.Config.PEM

  @pem """
  -----BEGIN PUBLIC KEY-----
  MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0vx7agoebGcQSuuPiLJX
  ZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tS
  oc/BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ/2W+5JsGY4Hc5n9yBXArwl93lqt
  7/RN5w6Cf0h4QyQ5v+65YGjQR0/FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0
  zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt+bFTWhAI4vMQFh6WeZu0f
  M4lFd2NcRwr3XPksINHaQ+G/xBniIqbw0Ls1jF44+csFCur+kEgU8awapJzKnqDK
  gwIDAQAB
  -----END PUBLIC KEY-----
  """

  @lines String.split(@pem, "\n", trim: true)

  describe "from_env/1" do
    test "reads the PEM text however its line breaks arrived" do
      for value <- [
            @pem,
            String.trim_trailing(@pem),
            Enum.join(@lines, "\r\n"),
            Enum.map_join(@lines, "\n", &("  " <> &1)),
            Enum.join(@lines, " "),
            Enum.join(@lines, "\\n"),
            Enum.join(@lines, "\\r\\n"),
            ~s("#{String.trim_trailing(@pem)}")
          ] do
        assert PEM.from_env(value) == {:ok, @pem}, inspect(value)
      end
    end

    test "reads the PEM text base64-encoded, with any wrapping or padding" do
      encoded = Base.encode64(@pem)

      for value <- [
            Base.encode64(@pem, padding: false),
            encoded,
            wrap(encoded, 76, "\n"),
            wrap(encoded, 64, "\n"),
            wrap(encoded, 76, "\n") <> "\n",
            wrap(encoded, 76, "\r\n"),
            @pem |> String.replace("\n", "\r\n") |> Base.encode64()
          ] do
        assert PEM.from_env(value) == {:ok, @pem}, inspect(value)
      end
    end

    test "keeps the block's own label, whatever key it holds" do
      pkcs1 =
        :public_key.pem_encode([
          :public_key.pem_entry_encode(
            :RSAPrivateKey,
            :public_key.generate_key({:rsa, 2048, 65_537})
          )
        ])

      {_, pkcs8} = JOSE.JWK.generate_key({:rsa, 2048}) |> JOSE.JWK.to_pem()

      for pem <- [pkcs1, pkcs8] do
        assert PEM.from_env(pem) == {:ok, String.trim_trailing(pem) <> "\n"}
      end

      assert {:ok, "-----BEGIN RSA PRIVATE KEY-----\n" <> _} =
               PEM.from_env(pkcs1)

      assert {:ok, "-----BEGIN PRIVATE KEY-----\n" <> _} = PEM.from_env(pkcs8)
    end

    test "says why a value holds no PEM block it can read" do
      first_line = hd(@lines)
      der_base64 = @lines |> Enum.slice(1..-2//1) |> Enum.join()
      docker_kept = @pem |> Base.encode64() |> String.slice(0, 76)

      for {value, reason} <- [
            {"", :empty},
            {"   ", :empty},
            {~s("LS0tLS1C"), :quoted},
            {"'LS0tLS1C'", :quoted},
            {"not base64!", :not_pem},
            {"garbage", :not_pem},
            {Base.encode64("hello"), :not_pem},
            {der_base64, :not_pem},
            {first_line, {:truncated, "PUBLIC KEY"}},
            {docker_kept, {:truncated, "PUBLIC KEY"}},
            {String.replace(@pem, "\nMIIB", "\n!IIB"), :damaged},
            {@pem <> @pem, :several_blocks},
            {String.replace(@pem, "PUBLIC KEY", "OPENSSH PRIVATE KEY"),
             :unknown_label}
          ] do
        assert PEM.from_env(value) == {:error, reason}, inspect(value)
      end
    end

    test "names no label when the BEGIN line lost its closing dashes" do
      [begin_line | rest] = @lines

      for damaged <- [
            String.trim_trailing(begin_line, "-"),
            String.replace_suffix(begin_line, "-----", "----")
          ],
          lines = [damaged | rest],
          value <- [
            Enum.join(lines, " "),
            Enum.join(lines, "\t"),
            Enum.join(lines, "\\n"),
            Enum.join(lines, "\n"),
            lines |> Enum.join(" ") |> Base.encode64()
          ] do
        assert PEM.from_env(value) == {:error, :unknown_label}, inspect(value)
      end
    end
  end

  defp wrap(text, width, line_break) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(width)
    |> Enum.map_join(line_break, &Enum.join/1)
  end
end
