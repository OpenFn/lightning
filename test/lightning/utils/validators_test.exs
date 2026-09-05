defmodule Lightning.ValidatorsTest do
  use ExUnit.Case, async: true

  alias Lightning.Validators

  import Ecto.Changeset
  import Lightning.Validators, only: [validate_uuid: 2, valid_uuid?: 1]

  defmodule Holder do
    use Ecto.Schema

    # Use :binary_id (not Ecto.UUID) to mirror the real schema fields the
    # validator guards (Job.id, Trigger.id, cron_cursor_job_id). Unlike
    # Ecto.UUID, :binary_id `cast/3` does NOT re-format a 16-byte binary into a
    # canonical hex UUID — it passes the raw string straight through, which is
    # exactly the value that later fails at `Ecto.UUID.dump/1` on insert.
    @primary_key false
    embedded_schema do
      field :ref_id, :binary_id
    end
  end

  defp changeset(value) do
    %Holder{}
    |> cast(%{ref_id: value}, [:ref_id])
    |> validate_uuid(:ref_id)
  end

  describe "validate_uuid/2" do
    test "rejects a 16-byte non-hex string (the dump/cast asymmetry)" do
      cs = changeset("__ID_JOB_Fetch__")
      refute cs.valid?
      assert cs.errors[:ref_id] == {"is not a valid UUID", []}
    end

    test "accepts a canonical UUID" do
      cs = changeset(Ecto.UUID.generate())
      assert cs.valid?
      assert cs.errors[:ref_id] == nil
    end

    test "passes through when the field is nil / absent" do
      assert changeset(nil).valid?

      assert %Holder{}
             |> cast(%{}, [:ref_id])
             |> validate_uuid(:ref_id)
             |> Map.fetch!(:valid?)
    end
  end

  describe "valid_uuid?/1" do
    test "accepts canonical UUIDs and rejects everything else" do
      assert valid_uuid?(Ecto.UUID.generate())
      # uppercase canonical still dumps
      assert valid_uuid?(String.upcase(Ecto.UUID.generate()))

      refute valid_uuid?(nil)
      refute valid_uuid?("not-a-uuid")
      # non-binary
      refute valid_uuid?(:an_atom)
      # raw 16-byte binary
      refute valid_uuid?(<<0::128>>)
    end
  end

  describe "invisible_only?/1" do
    # The fixture is generated from this predicate and asserted against the
    # client's copy in assets/test/utils/nameValidation.test.ts.
    @fixture "test/fixtures/invisible_codepoints.json"

    @named [
      {0x00AD, "soft hyphen"},
      {0x034F, "combining grapheme joiner"},
      {0x061C, "arabic letter mark"},
      {0x115F, "hangul choseong filler"},
      {0x1160, "hangul jungseong filler"},
      {0x17B4, "khmer vowel inherent aq"},
      {0x180B, "mongolian free variation selector one"},
      {0x180E, "mongolian vowel separator"},
      {0x200B, "zero width space"},
      {0x200D, "zero width joiner"},
      {0x200F, "right-to-left mark"},
      {0x202E, "right-to-left override"},
      {0x2060, "word joiner"},
      {0x2065, "unassigned default ignorable"},
      {0x206F, "nominal digit shapes"},
      {0x2800, "braille pattern blank"},
      {0x3164, "hangul filler"},
      {0xFE00, "variation selector-1"},
      {0xFE0D, "variation selector-14"},
      {0xFE0F, "variation selector-16"},
      {0xFEFF, "byte order mark"},
      {0xFFA0, "halfwidth hangul filler"},
      {0xFFFB, "interlinear annotation terminator"},
      {0x13430, "egyptian hieroglyph vertical joiner"},
      {0xE0001, "language tag"},
      {0xE007F, "cancel tag"},
      {0xE0100, "variation selector-17"},
      {0xE01EF, "variation selector-256"}
    ]

    test "the ones the old hand-written list missed are all caught" do
      for {codepoint, label} <- @named do
        name = <<codepoint::utf8>>

        assert Validators.invisible_only?(name),
               "expected #{label} (U+#{Integer.to_string(codepoint, 16)}) to " <>
                 "count as invisible"
      end
    end

    test "a run of them is caught, not just one" do
      # A per-grapheme check used to fuse a joiner-led run into one cluster and
      # miss it.
      assert Validators.invisible_only?("\u{200D}\u{200D}")
      assert Validators.invisible_only?("\u{200B}\u{FEFF}\u{00AD}\u{FE0F}")
      assert Validators.invisible_only?(String.duplicate("\u{200D}", 20))
    end

    test "a name that merely contains one is left alone" do
      for {label, name} <- [
            {"emoji zwj sequence",
             "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"},
            {"devanagari zwnj", "\u{0915}\u{094D}\u{200C}\u{0937}"},
            {"arabic zwj", "\u{0644}\u{200D}\u{0627}"},
            {"variation selector on a symbol", "\u{2764}\u{FE0F}"},
            {"invisible in the middle", "a\u{200B}b"},
            {"plain", "step"}
          ] do
        refute Validators.invisible_only?(name),
               "expected #{label} to be a real name"
      end
    end

    test "the empty string and ordinary whitespace are not this rule's job" do
      # trim/1 empties these before the check runs.
      refute Validators.invisible_only?("")
      refute Validators.invisible_only?(" ")
      refute Validators.invisible_only?("\t")
    end

    test "the fixture still matches this predicate" do
      %{"count" => count, "ranges" => ranges} =
        @fixture |> File.read!() |> Jason.decode!()

      codepoints =
        Enum.flat_map(ranges, fn [lo, hi] -> Enum.to_list(lo..hi) end)

      assert length(codepoints) == count

      for codepoint <- codepoints do
        assert Validators.invisible_only?(<<codepoint::utf8>>),
               "fixture holds U+#{Integer.to_string(codepoint, 16)} but the " <>
                 "predicate does not; regenerate it"
      end

      missing =
        Enum.reject(0..0x10FFFF, fn codepoint ->
          codepoint in 0xD800..0xDFFF or
            not Validators.invisible_only?(<<codepoint::utf8>>) or
            codepoint in codepoints
        end)

      assert missing == [],
             "the predicate now matches codepoints the fixture does not; " <>
               "regenerate it"
    end
  end

  # Every rule here guards a `:string` field, but a changeset can carry nil, and
  # the deep jsonb walk meets whatever a map holds. These clauses are what stops
  # a validator raising on a value it was not written for.
  describe "values that are not strings" do
    defmodule Named do
      use Ecto.Schema

      @primary_key false
      embedded_schema do
        field :name, :string
        field :payload, :map
      end
    end

    defp named(attrs) do
      cast(%Named{}, attrs, [:name, :payload])
    end

    test "a nil name is left to validate_required rather than refused here" do
      cs = named(%{name: nil}) |> Validators.validate_name(:name)

      assert cs.errors[:name] == nil
    end

    test "invisible_only? says no to anything that is not a string" do
      refute Validators.invisible_only?(nil)
      refute Validators.invisible_only?(42)
      refute Validators.invisible_only?(:atom)
    end

    test "a nil field passes the null byte check" do
      cs =
        named(%{name: nil})
        |> Validators.validate_no_null_bytes(:name, "no null bytes")

      assert cs.errors[:name] == nil
    end

    test "the deep walk reaches atoms, numbers and nested lists" do
      cs =
        named(%{payload: %{a: [1, :ok, %{"b" => "fine"}], c: nil}})
        |> Validators.validate_no_null_bytes_deep(:payload, "no null bytes")

      assert cs.errors[:payload] == nil
    end

    test "the deep walk still catches a NUL under all of that" do
      cs =
        named(%{payload: %{a: [1, :ok, %{"b" => "bad\0"}]}})
        |> Validators.validate_no_null_bytes_deep(:payload, "no null bytes")

      refute cs.valid?
    end

    test "a name that is not valid UTF-8 is left as it is rather than raising" do
      cs = named(%{name: <<0xFF, 0xFE>>}) |> Validators.validate_name(:name)

      # NFC cannot normalise it, so normalisation returns it untouched and the
      # charset rule refuses it. The point is that it does not raise.
      refute cs.valid?
    end
  end
end
