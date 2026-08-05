defmodule Lightning.Adaptors.Repo.AdaptorTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Repo.Adaptor

  @valid_attrs %{
    name: "@openfn/language-http",
    source: :npm,
    latest_version: "1.2.3",
    checked_at: ~U[2026-05-14 00:00:00.000000Z]
  }

  describe "changeset/2 — required fields" do
    test "is valid with the minimum required set" do
      changeset = Adaptor.changeset(%Adaptor{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires :name" do
      changeset =
        Adaptor.changeset(%Adaptor{}, Map.delete(@valid_attrs, :name))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :name)
    end

    test "requires :source" do
      changeset =
        Adaptor.changeset(%Adaptor{}, Map.delete(@valid_attrs, :source))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :source)
    end

    test "requires :latest_version" do
      changeset =
        Adaptor.changeset(
          %Adaptor{},
          Map.delete(@valid_attrs, :latest_version)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :latest_version)
    end

    test "requires :checked_at" do
      changeset =
        Adaptor.changeset(%Adaptor{}, Map.delete(@valid_attrs, :checked_at))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :checked_at)
    end
  end

  describe "changeset/2 — :name length cap" do
    test "rejects :name longer than 214 characters (npm pkg limit)" do
      too_long = String.duplicate("a", 215)

      changeset =
        Adaptor.changeset(%Adaptor{}, %{@valid_attrs | name: too_long})

      refute changeset.valid?

      assert Enum.any?(
               errors_on(changeset, :name),
               &(&1 =~ "should be at most")
             )
    end

    test "accepts :name of exactly 214 characters" do
      ok = String.duplicate("a", 214)

      assert Adaptor.changeset(%Adaptor{}, %{@valid_attrs | name: ok}).valid?
    end
  end

  describe "changeset/2 — :source Ecto.Enum cast" do
    test "round-trips atom :npm" do
      changeset =
        Adaptor.changeset(%Adaptor{}, %{@valid_attrs | source: :npm})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :source) == :npm
    end

    test "round-trips atom :local" do
      changeset =
        Adaptor.changeset(%Adaptor{}, %{@valid_attrs | source: :local})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :source) == :local
    end

    test "casts the string form \"npm\" back to the :npm atom" do
      changeset =
        Adaptor.changeset(%Adaptor{}, %{@valid_attrs | source: "npm"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :source) == :npm
    end

    test "casts the string form \"local\" back to the :local atom" do
      changeset =
        Adaptor.changeset(%Adaptor{}, %{@valid_attrs | source: "local"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :source) == :local
    end

    test "rejects an unknown source atom" do
      changeset =
        Adaptor.changeset(%Adaptor{}, %{@valid_attrs | source: :other})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset, :source)
    end

    test "rejects an unknown source string" do
      changeset =
        Adaptor.changeset(%Adaptor{}, %{@valid_attrs | source: "other"})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset, :source)
    end
  end

  describe "changeset/2 — icon ext inclusion" do
    test "accepts \"png\" for :icon_square_ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_square_ext: "png",
          icon_square_sha256: :crypto.strong_rand_bytes(32)
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "accepts \"svg\" for :icon_square_ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_square_ext: "svg",
          icon_square_sha256: :crypto.strong_rand_bytes(32)
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "rejects an unknown :icon_square_ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_square_ext: "gif",
          icon_square_sha256: :crypto.strong_rand_bytes(32)
        })

      changeset = Adaptor.changeset(%Adaptor{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset, :icon_square_ext)
    end

    test "accepts \"png\" for :icon_rectangle_ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_rectangle_ext: "png",
          icon_rectangle_sha256: :crypto.strong_rand_bytes(32)
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "accepts \"svg\" for :icon_rectangle_ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_rectangle_ext: "svg",
          icon_rectangle_sha256: :crypto.strong_rand_bytes(32)
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "rejects an unknown :icon_rectangle_ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_rectangle_ext: "jpeg",
          icon_rectangle_sha256: :crypto.strong_rand_bytes(32)
        })

      changeset = Adaptor.changeset(%Adaptor{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset, :icon_rectangle_ext)
    end
  end

  describe "changeset/2 — validate_icon_sha256_pair (square)" do
    test "accepts both nil (no icon)" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_square_ext: nil,
          icon_square_sha256: nil
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "accepts both set" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_square_ext: "png",
          icon_square_sha256: :crypto.strong_rand_bytes(32)
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "rejects ext set without sha256" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_square_ext: "png",
          icon_square_sha256: nil
        })

      changeset = Adaptor.changeset(%Adaptor{}, attrs)
      refute changeset.valid?

      assert Enum.any?(
               errors_on(changeset, :icon_square_sha256),
               &(&1 =~ "must not be nil")
             )
    end

    test "rejects sha256 set without ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_square_ext: nil,
          icon_square_sha256: :crypto.strong_rand_bytes(32)
        })

      changeset = Adaptor.changeset(%Adaptor{}, attrs)
      refute changeset.valid?

      assert Enum.any?(
               errors_on(changeset, :icon_square_sha256),
               &(&1 =~ "must be nil")
             )
    end
  end

  describe "changeset/2 — validate_icon_sha256_pair (rectangle)" do
    test "accepts both nil (no icon)" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_rectangle_ext: nil,
          icon_rectangle_sha256: nil
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "accepts both set" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_rectangle_ext: "svg",
          icon_rectangle_sha256: :crypto.strong_rand_bytes(32)
        })

      assert Adaptor.changeset(%Adaptor{}, attrs).valid?
    end

    test "rejects ext set without sha256" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_rectangle_ext: "svg",
          icon_rectangle_sha256: nil
        })

      changeset = Adaptor.changeset(%Adaptor{}, attrs)
      refute changeset.valid?

      assert Enum.any?(
               errors_on(changeset, :icon_rectangle_sha256),
               &(&1 =~ "must not be nil")
             )
    end

    test "rejects sha256 set without ext" do
      attrs =
        Map.merge(@valid_attrs, %{
          icon_rectangle_ext: nil,
          icon_rectangle_sha256: :crypto.strong_rand_bytes(32)
        })

      changeset = Adaptor.changeset(%Adaptor{}, attrs)
      refute changeset.valid?

      assert Enum.any?(
               errors_on(changeset, :icon_rectangle_sha256),
               &(&1 =~ "must be nil")
             )
    end
  end

  describe "changeset/2 — unique_constraint" do
    test "registers a unique_constraint on [:name, :source]" do
      changeset = Adaptor.changeset(%Adaptor{}, @valid_attrs)

      assert Enum.any?(changeset.constraints, fn c ->
               c.type == :unique and
                 c.constraint == "adaptors_name_source_index"
             end)
    end
  end

  defp errors_on(changeset, field) do
    for {f, {msg, _opts}} <- changeset.errors, f == field, do: msg
  end
end
