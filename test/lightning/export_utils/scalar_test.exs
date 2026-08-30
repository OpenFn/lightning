defmodule Lightning.ExportUtils.ScalarTest do
  use ExUnit.Case, async: true

  alias Lightning.ExportUtils.Scalar

  # The shapes the export used to emit bare. Anything matching these has to
  # keep coming out byte for byte the same, otherwise every customer repo that
  # tracks a project spec picks up a diff.
  @old_value_regex ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.> ]*[a-zA-Z0-9]\z/
  @old_key_regex ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.>]*[a-zA-Z0-9]\z/

  # U+0085 is a C1 control character and U+FFFE is a non-character. Built from
  # their code points rather than typed in, so they stay visible in the source.
  @nel "a" <> <<0x85::utf8>> <> "b"
  @noncharacter "a" <> <<0xFFFE::utf8>> <> "b"

  @nasty_strings [
    "MailChimp June'24",
    "Vérifier l'état",
    "患者確認",
    "Flujo 1: Registro",
    "off",
    "no",
    "null",
    "~",
    "1.0",
    "2026-08-27",
    ".inf",
    "a\"b",
    "a\\b",
    "a\nb",
    "a\tb",
    " leading",
    "trailing ",
    "#hash",
    "-dash",
    "*ref",
    "&anchor",
    "!tag",
    "%directive",
    "`tick",
    "@at",
    "step 🎉",
    "a",
    String.duplicate("n", 300)
  ]

  describe "encode_value/1 bare" do
    test "leaves the historic bare shapes untouched" do
      for value <- [
            "a-test-project",
            "workflow 1",
            "webhook job",
            "on_job_failure",
            "cannonical-user@lightning.com",
            "cannonical-user@lightning.com-new-credential",
            "webhook->webhook-job",
            "Demo-1. Punto Solidario",
            "WF 1 - SIDAInfo indicators to DHIS2"
          ] do
        assert Scalar.encode_value(value) == value
      end
    end
  end

  describe "encode_value/1 single quoted" do
    test "doubles an embedded single quote" do
      assert Scalar.encode_value("MailChimp June'24") == "'MailChimp June''24'"
      assert Scalar.encode_value("Vérifier l'état") == "'Vérifier l''état'"
      assert Scalar.encode_value("''") == "''''''"
    end

    test "keeps the historic single quoted style for everything printable" do
      assert Scalar.encode_value("Flujo 1: Registro") == "'Flujo 1: Registro'"
      assert Scalar.encode_value("nueva solicitud ") == "'nueva solicitud '"
      assert Scalar.encode_value("#hash") == "'#hash'"
      assert Scalar.encode_value("患者確認") == "'患者確認'"
      assert Scalar.encode_value("a") == "'a'"
      assert Scalar.encode_value("a\"b") == "'a\"b'"
      assert Scalar.encode_value("a\\b") == "'a\\b'"
    end
  end

  describe "encode_value/1 double quoted" do
    test "falls back to double quotes when a single quoted scalar cannot hold it" do
      assert Scalar.encode_value("a\nb") == "\"a\\nb\""
      assert Scalar.encode_value("a\rb") == "\"a\\rb\""
      assert Scalar.encode_value("a\tb") == "\"a\\tb\""
      assert Scalar.encode_value("a\0b") == "\"a\\0b\""
      assert Scalar.encode_value("a\ab") == "\"a\\x07b\""
      assert Scalar.encode_value("a\eb") == "\"a\\x1bb\""
      assert Scalar.encode_value("a\x7Fb") == "\"a\\x7fb\""
      assert Scalar.encode_value(@nel) == "\"a\\x85b\""
      assert Scalar.encode_value(@noncharacter) == "\"a\\ufffeb\""
    end

    test "escapes backslashes and double quotes in the double quoted branch" do
      assert Scalar.encode_value("a\\b\nc\"d") == "\"a\\\\b\\nc\\\"d\""
    end

    test "leaves ordinary unicode alone in the double quoted branch" do
      assert Scalar.encode_value("患者\n確認") == "\"患者\\n確認\""
    end
  end

  describe "encode_key/1" do
    test "leaves the historic bare shapes untouched" do
      for key <- [
            "a-test-project",
            "workflow-1",
            "webhook-job",
            "cannonical-user@lightning.com-new-credential",
            "webhook->webhook-job",
            "Demo-1.-Punto-Solidario",
            "inform-to-unicare-bih-demo"
          ] do
        assert Scalar.encode_key(key) == key
      end
    end

    test "uses double quotes, which is the style keys have always used" do
      assert Scalar.encode_key("Flujo-1:-Registro") == "\"Flujo-1:-Registro\""
      assert Scalar.encode_key("with space") == "\"with space\""
      assert Scalar.encode_key("患者確認") == "\"患者確認\""
      assert Scalar.encode_key("a") == "\"a\""
    end

    test "escapes backslashes, double quotes and control characters" do
      assert Scalar.encode_key("a\"b") == "\"a\\\"b\""
      assert Scalar.encode_key("a\\b") == "\"a\\\\b\""
      assert Scalar.encode_key("a\\\"b") == "\"a\\\\\\\"b\""
      assert Scalar.encode_key("a\nb") == "\"a\\nb\""
      assert Scalar.encode_key("a\0b") == "\"a\\0b\""
    end

    test "leaves a single quote alone, since keys are double quoted" do
      assert Scalar.encode_key("MailChimp-June'24") == "\"MailChimp-June'24\""
    end
  end

  describe "YAML typed lookalikes" do
    # Narrowed in #4577 to what yamerl and yaml@2.7.1 actually resolve. The
    # measured corpus and the round-trip proof are in the "typed?/1 corpus"
    # describe at the bottom of this file.
    @booleans_and_null ~w(true True TRUE false False FALSE null Null NULL ~)

    @integers ~w(0 7 08 2026 +5 -5 0x1F 0xff 0o17 007)

    @floats ~w(
      1.0 0.5 .5 1e3 1E3 1.5e-3 -1.5 .inf .Inf .INF -.Inf +.inf .nan .NaN .NAN
    )

    # Neither parser resolves any of these, in either position, so quoting them
    # would only churn synced repos. Every one was a legal job name under the
    # charset rule this branch removed.
    @not_typed ~w(
      y Y n N yes Yes YES no No NO on On ON off Off OFF
      1_000 0b1010 1:30 0X1F 0O17
    ) ++ ["2026-08-27", "2026-8-7", "2026-08-27T10:00:00Z"]

    test "the empty string is never bare" do
      assert Scalar.encode_value("") == "''"
      assert Scalar.encode_key("") == "\"\""
    end

    test "booleans and null are quoted" do
      for word <- @booleans_and_null do
        assert Scalar.encode_value(word) != word,
               "expected #{inspect(word)} to be quoted as a value"

        assert Scalar.encode_key(word) != word,
               "expected #{inspect(word)} to be quoted as a key"
      end
    end

    test "integers are quoted" do
      for int <- @integers do
        assert Scalar.encode_value(int) != int,
               "expected #{inspect(int)} to be quoted as a value"
      end
    end

    test "floats are quoted" do
      for float <- @floats do
        assert Scalar.encode_value(float) != float,
               "expected #{inspect(float)} to be quoted as a value"
      end
    end

    test "the words and date shapes neither parser resolves stay bare" do
      for value <- @not_typed do
        # Only the ones the historic bare shape allows in the first place; the
        # rest are quoted for reasons that have nothing to do with typing.
        if Regex.match?(
             ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.> ]*[a-zA-Z0-9]\z/,
             value
           ) do
          assert Scalar.encode_value(value) == value,
                 "expected #{inspect(value)} to stay bare as a value"
        end
      end
    end

    test "names that only look like typed scalars stay bare" do
      for value <- [
            "no-op",
            "onboarding",
            "offer",
            "yesterday",
            "nullify",
            "true north",
            "1.0.1",
            "2026-08-27-report",
            "v1.0",
            "1e3x",
            "0x1G"
          ] do
        assert Scalar.encode_value(value) == value,
               "expected #{inspect(value)} to stay bare"
      end
    end
  end

  describe "the trailing newline hole in the old regexes" do
    test "a trailing newline no longer slips through as a bare scalar" do
      # The old regexes were anchored with ^ and $, and $ matches before a
      # newline at the end of the subject, so a trailing newline was emitted
      # bare and injected a blank line into the spec.
      assert Regex.match?(
               ~r/^[a-zA-Z0-9][a-zA-Z0-9_\-@\.> ]*[a-zA-Z0-9]$/,
               "workflow 1\n"
             )

      assert Scalar.encode_value("workflow 1\n") == "\"workflow 1\\n\""
      assert Scalar.encode_key("workflow-1\n") == "\"workflow-1\\n\""
    end
  end

  describe "strings taken from real exported project specs" do
    # Lifted from three specs exported from production. Names only, no owners.
    test "reproduces the keys those specs already contain" do
      assert Scalar.encode_key("Flujo-1:-Registro-en-PS-y-gestión-de-perfiles") ==
               ~s("Flujo-1:-Registro-en-PS-y-gestión-de-perfiles")

      assert Scalar.encode_key(
               "Flujo-2:-Finalización-y-distribución-de-evaluaciones-de-SIUBEN"
             ) ==
               ~s("Flujo-2:-Finalización-y-distribución-de-evaluaciones-de-SIUBEN")

      assert Scalar.encode_key("Demo-1.-Punto-Solidario") ==
               "Demo-1.-Punto-Solidario"

      assert Scalar.encode_key("WF-1---SIDAInfo-indicators-to-DHIS2") ==
               "WF-1---SIDAInfo-indicators-to-DHIS2"

      assert Scalar.encode_key("webhook->obtiene-solicitud-en-PS") ==
               "webhook->obtiene-solicitud-en-PS"

      assert Scalar.encode_key("inform-to-unicare-bih-demo") ==
               "inform-to-unicare-bih-demo"
    end

    test "reproduces the values those specs already contain" do
      assert Scalar.encode_value("Flujo 1: Registro en PS y gestión de perfiles") ==
               ~s('Flujo 1: Registro en PS y gestión de perfiles')

      assert Scalar.encode_value("evaluación rechazada") ==
               ~s('evaluación rechazada')

      assert Scalar.encode_value("nueva solicitud ") == ~s('nueva solicitud ')

      assert Scalar.encode_value("Demo-1. Punto Solidario") ==
               "Demo-1. Punto Solidario"

      assert Scalar.encode_value("WF 1 - SIDAInfo indicators to DHIS2") ==
               "WF 1 - SIDAInfo indicators to DHIS2"

      assert Scalar.encode_value("If validation passes") ==
               "If validation passes"

      assert Scalar.encode_value("Attachment Exists") == "Attachment Exists"
    end
  end

  describe "round trip" do
    test "every encoded value parses back to the string it came from" do
      for value <- round_trip_corpus() do
        encoded = Scalar.encode_value(value)

        assert {:ok, %{"k" => ^value}} =
                 YamlElixir.read_from_string("k: " <> encoded),
               "value #{inspect(value)} encoded as #{inspect(encoded)} did not round trip"
      end
    end

    test "every encoded key parses back to the string it came from" do
      for key <- round_trip_corpus() do
        encoded = Scalar.encode_key(key)

        assert {:ok, parsed} = YamlElixir.read_from_string(encoded <> ": 1")

        assert Map.keys(parsed) == [key],
               "key #{inspect(key)} encoded as #{inspect(encoded)} did not round trip"
      end
    end

    test "encoded scalars survive being nested inside a mapping" do
      for value <- round_trip_corpus() do
        document = """
        workflows:
          #{Scalar.encode_key(value)}:
            name: #{Scalar.encode_value(value)}
        """

        assert {:ok, %{"workflows" => workflows}} =
                 YamlElixir.read_from_string(document)

        assert Map.keys(workflows) == [value]
        assert workflows[value] == %{"name" => value}
      end
    end
  end

  describe "byte compatibility" do
    test "anything the old regex emitted bare is still emitted bare" do
      for value <- byte_compat_corpus(),
          Regex.match?(@old_value_regex, value),
          not typed_lookalike?(value) do
        assert Scalar.encode_value(value) == value,
               "value #{inspect(value)} used to be bare and no longer is"
      end
    end

    test "anything the old key regex emitted bare is still emitted bare" do
      for key <- byte_compat_corpus(),
          Regex.match?(@old_key_regex, key),
          not typed_lookalike?(key) do
        assert Scalar.encode_key(key) == key,
               "key #{inspect(key)} used to be bare and no longer is"
      end
    end

    test "the sweep actually reaches the bare branch" do
      bare =
        byte_compat_corpus()
        |> Enum.filter(&Regex.match?(@old_value_regex, &1))
        |> Enum.reject(&typed_lookalike?/1)

      assert length(bare) > 500
    end
  end

  defp round_trip_corpus do
    @nasty_strings ++
      [
        "Flujo 1: Registro en PS y gestión de perfiles",
        "Flujo-1:-Registro-en-PS-y-gestión-de-perfiles",
        "nueva solicitud ",
        "evaluación rechazada",
        "workflow 1",
        "webhook->webhook-job",
        "",
        "''",
        "\"",
        "\\",
        "\\n",
        "a: b",
        "a, b",
        "[a]",
        "{a}",
        "? a",
        "---",
        "...",
        "a\0b",
        "a\ab",
        "a\eb",
        "a\x7Fb",
        @nel,
        @noncharacter,
        "0x1F",
        "0o17",
        "+5",
        "1_000",
        "-.Inf",
        ".nan",
        "1e3",
        "2026-08-27T10:00:00Z"
      ] ++ byte_compat_corpus()
  end

  # A deterministic sweep of the alphabet the old regexes allowed, so the byte
  # compatibility claim is checked against more than a handful of examples.
  defp byte_compat_corpus do
    alphanumeric = Enum.concat([?a..?z, ?A..?Z, ?0..?9])
    middle = alphanumeric ++ ~c(_-@.> )
    middle_size = length(middle)

    generated =
      for first <- alphanumeric, last <- alphanumeric do
        body =
          for i <- 0..3, into: "" do
            <<Enum.at(middle, rem(first * 31 + last * 7 + i * 13, middle_size))>>
          end

        <<first>> <> body <> <<last>>
      end

    generated ++
      [
        "a-test-project",
        "workflow 1",
        "on success",
        "on_job_failure",
        "cannonical-user@lightning.com",
        "webhook->webhook-job",
        "Demo-1. Punto Solidario",
        "WF 1 - SIDAInfo indicators to DHIS2",
        "off",
        "null",
        "1.0",
        "2026-08-27",
        "1_000",
        "0x1F"
      ]
  end

  # A second, independent statement of "YAML would resolve this to something
  # other than a string". Written out again rather than reaching into the
  # module under test, so the sweep above is a real check and not a tautology.
  @lookalike_words ~w(y n yes no on off true false null ~)
  @lookalike_int ~r/\A[-+]?(0b[01_]+|0o[0-7_]+|0x[0-9a-fA-F_]+|[0-9][0-9_]*(:[0-5]?[0-9])*)\z/
  @lookalike_float ~r/
    \A
    (
      [-+]?\.(inf|Inf|INF)
    | \.(nan|NaN|NAN)
    | [-+]?([0-9][0-9_]*)?\.[0-9_]*([eE][-+]?[0-9]+)?
    | [-+]?[0-9][0-9_]*[eE][-+]?[0-9]+
    | [-+]?[0-9][0-9_]*(:[0-5]?[0-9])+\.[0-9_]*
    )
    \z
  /x
  @lookalike_timestamp ~r/
    \A
    \d{4}-\d{1,2}-\d{1,2}
    (
      ([Tt]|[ \t]+)
      \d{1,2}:\d{2}:\d{2}(\.\d*)?
      ([ \t]*(Z|[-+]\d{1,2}(:\d{2})?))?
    )?
    \z
  /x

  defp typed_lookalike?(""), do: true

  defp typed_lookalike?(string) do
    String.downcase(string) in @lookalike_words or
      Regex.match?(@lookalike_int, string) or
      Regex.match?(@lookalike_float, string) or
      Regex.match?(@lookalike_timestamp, string)
  end

  describe "typed?/1 corpus (what the parsers actually resolve)" do
    # Every entry here was measured against both parsers this project ships
    # against, as a value and as a key: yamerl through YamlElixir, and
    # yaml@2.7.1 in assets/node_modules. Do not add to @resolved without
    # running the string through both first, and do not move anything out of
    # @plain without doing the same. Over-quoting is not free: every one of
    # these is a legal name, and a quoting change is a diff in every synced
    # project repo that holds one.

    # Resolved by at least one parser in at least one position, so it must
    # never be emitted bare.
    @resolved [
      "true",
      "True",
      "TRUE",
      "false",
      "False",
      "FALSE",
      "null",
      "Null",
      "NULL",
      "~",
      "",
      "42",
      "0",
      "00",
      "007",
      "08",
      "0x1f",
      "0x1F",
      "0o17",
      "0x",
      "1.0",
      "1.",
      "1e3",
      "1E5",
      ".5",
      ".inf",
      ".nan",
      ".NaN"
    ]

    # Handed back as the exact string we wrote, by both parsers, in both
    # positions. Quoting these would buy nothing and cost a diff.
    @plain [
      "y",
      "Y",
      "n",
      "N",
      "yes",
      "Yes",
      "YES",
      "no",
      "No",
      "NO",
      "on",
      "On",
      "ON",
      "off",
      "Off",
      "OFF",
      "tRue",
      "NULl",
      "1_000",
      "1_0.5",
      "0b101",
      "0X1F",
      "0O17",
      "1:30",
      "2026-08-27",
      "2026-8-7",
      "0 0 1 1 1",
      "step",
      "my job"
    ]

    test "everything a parser resolves comes back quoted" do
      for value <- @resolved do
        encoded = Scalar.encode_value(value)

        assert String.starts_with?(encoded, "'") or
                 String.starts_with?(encoded, "\""),
               "expected #{inspect(value)} to be quoted, got #{encoded}"
      end
    end

    test "everything both parsers leave alone is emitted bare" do
      for value <- @plain do
        encoded = Scalar.encode_value(value)

        if Regex.match?(
             ~r/\A[a-zA-Z0-9][a-zA-Z0-9_\-@\.> ]*[a-zA-Z0-9]\z/,
             value
           ) do
          assert encoded == value,
                 "expected #{inspect(value)} to stay bare, got #{encoded}"
        end
      end
    end

    test "every one of them round-trips through yamerl as the string we wrote" do
      for value <- @resolved ++ @plain do
        doc = "k: #{Scalar.encode_value(value)}\n"

        assert {:ok, %{"k" => ^value}} = YamlElixir.read_from_string(doc),
               "value #{inspect(value)} did not round-trip: #{doc}"
      end
    end

    test "and as a key, where a bare number would come back as a number" do
      # The empty string cannot be a mapping key in this export; nothing
      # generates one.
      for value <- Enum.reject(@resolved, &(&1 == "")) ++ @plain do
        doc = "#{Scalar.encode_key(value)}: 1\n"

        assert {:ok, parsed} = YamlElixir.read_from_string(doc),
               "key #{inspect(value)} did not parse: #{doc}"

        assert Map.keys(parsed) == [value],
               "key #{inspect(value)} came back as #{inspect(Map.keys(parsed))}"
      end
    end
  end

  describe "encode_block/2" do
    # The corpus below was round-tripped through both parsers this project
    # ships against, yamerl and yaml@2.7.1. Before #4577 the leading-space, CR
    # and multiple-trailing-newline rows all lost data or failed to parse
    # (issue #2966).
    @block_cases [
      {"plain", "fn(state => state)"},
      {"two lines", "line1\nline2"},
      {"trailing newline", "line1\nline2\n"},
      {"blank line inside", "line1\n\nline2"},
      {"leading space", " leading space"},
      {"two leading spaces", "  two leading\nsecond"},
      {"leading blank then space", "\n  indented first"},
      {"leading tab", "\tleading tab"},
      {"crlf", "a\r\nb"},
      {"lone cr", "a\rb"},
      {"empty", ""},
      {"two trailing newlines", "a\n\n"},
      # Crossed shapes. The indicator and the chomping indicator are chosen
      # independently, so a body that needs both used to get only the first
      # and lose the newlines the second exists to keep.
      {"leading space and two trailing", "  indented\nnext\n\n"},
      {"leading space and three trailing", " x\n\n\n"},
      {"leading tab and two trailing", "\tx\n\n"},
      {"leading blank, space and trailing", "\n  x\n\n"},
      {"whitespace only", "   "},
      {"trailing whitespace line", "a\n   \n"},
      {"three trailing newlines", "a\n\n\n"},
      {"only newlines", "\n\n"},
      {"trailing space", "trailing space \nb"},
      {"indented second line", "a\n  indented"},
      {"quote and colon", "a: 'b'\nc"}
    ]

    test "every case round-trips, exactly or with the historic trailing newline" do
      for {label, value} <- @block_cases do
        doc = "root:\n  body: #{Scalar.encode_block(value, "  ")}\n"

        assert {:ok, %{"root" => %{"body" => got}}} =
                 YamlElixir.read_from_string(doc),
               "#{label} did not parse:\n#{doc}"

        assert got == value or got == value <> "\n",
               "#{label} lost data: wrote #{inspect(value)}, read #{inspect(got)}"
      end
    end

    test "the historic shape is kept byte for byte wherever it was not broken" do
      # Anything without a CR, without a leading space on its first content
      # line, and with fewer than two trailing newlines must come out exactly
      # as this module has always written it. A change here is a diff in every
      # synced project repo.
      historic = fn value ->
        lines =
          value
          |> String.split("\n")
          |> Enum.map_join("\n", fn line -> "    #{line}" end)

        "|\n" <> lines
      end

      unbroken =
        for {label, value} <- @block_cases,
            not String.contains?(value, "\r"),
            not String.starts_with?(String.trim_leading(value, "\n"), " "),
            value == String.replace_trailing(value, "\n\n", "\n"),
            do: {label, value}

      refute unbroken == [],
             "every case was filtered out, so this test asserted nothing"

      for {label, value} <- unbroken do
        assert Scalar.encode_block(value, "  ") == historic.(value),
               "#{label} changed shape"
      end
    end

    test "a carriage return falls back to the quoted form, which escapes it" do
      assert Scalar.encode_block("a\r\nb", "  ") == "\"a\\r\\nb\""
      assert Scalar.encode_block("a\rb", "  ") == "\"a\\rb\""
    end

    test "a leading space gets an explicit indentation indicator" do
      assert Scalar.encode_block(" x", "  ") == "|2\n     x"
    end

    test "more than one trailing newline is kept rather than clipped" do
      assert Scalar.encode_block("a\n\n", "  ") == "|+\n    a\n    "
    end

    test "a value needing both indicators gets both" do
      assert Scalar.encode_block(" x\n\n", "  ") == "|2+\n     x\n    "
    end

    test "a whitespace-only value is quoted, where the parsers disagree" do
      # yamerl keeps the spaces, the npm parser returns "". The empty string
      # itself keeps its historic block shape.
      assert Scalar.encode_block("   ", "  ") == "'   '"
      assert Scalar.encode_block("", "  ") == "|\n    "
    end
  end

  describe "the block scalar fixture" do
    # test/fixtures/block_scalars.json is the one corpus both parsers see. This
    # half pins the encoder output and checks yamerl; assets/test/yaml/
    # blockScalars.test.ts parses the same documents with the npm parser, which
    # no Elixir test can run and which disagreed with yamerl on the `|2` shape
    # until #4577.
    @fixture "test/fixtures/block_scalars.json"

    setup do
      %{cases: @fixture |> File.read!() |> Jason.decode!()}
    end

    test "the encoder still produces exactly the documents in it", %{
      cases: cases
    } do
      for %{"label" => label, "value" => value, "document" => document} <-
            cases do
        expected = "root:\n  body: #{Scalar.encode_block(value, "  ")}\n"

        assert document == expected,
               "#{label} drifted from the fixture; regenerate it and check " <>
                 "both parsers"
      end
    end

    test "every document round-trips through yamerl", %{cases: cases} do
      for %{"label" => label, "value" => value, "document" => document} <-
            cases do
        assert {:ok, %{"root" => %{"body" => got}}} =
                 YamlElixir.read_from_string(document),
               "#{label} did not parse"

        assert got == value or got == value <> "\n",
               "#{label} lost data: wrote #{inspect(value)}, read #{inspect(got)}"
      end
    end
  end

  describe "values made of nothing" do
    test "the empty string is quoted, because bare it reads back as null" do
      # Value and key take different quoting paths, so pin both.
      assert Scalar.encode_value("") == "''"
      assert Scalar.encode_key("") == ~s("")

      assert {:ok, [%{"" => value}]} =
               YamlElixir.read_all_from_string(
                 Scalar.encode_key("") <> ": " <> Scalar.encode_value("")
               )

      assert value == ""
    end

    test "a value that is only newlines keeps every one of them" do
      # These have no content line for the reader to measure the block
      # against, so they need `|+` to stop the newlines being clipped away.
      # The document's own trailing newline is part of what makes this work,
      # which is why the assertion builds the whole document rather than
      # reading the block in isolation.
      for value <- ["\n", "\n\n", "\n\n\n"] do
        document = "k: " <> Scalar.encode_block(value, "  ") <> "\n"

        assert {:ok, [%{"k" => got}]} =
                 YamlElixir.read_all_from_string(document),
               "#{inspect(value)} did not parse: #{document}"

        assert got == value,
               "#{inspect(value)} came back as #{inspect(got)}"
      end
    end
  end
end
