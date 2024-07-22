defmodule Lightning.Encrypted.EmbeddedBinaryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Encrypted.EmbeddedBinary

  test "dump/1 with nil input" do
    assert {:ok, nil} = EmbeddedBinary.dump(nil)
  end

  test "load/1 with nil input" do
    assert {:ok, nil} = EmbeddedBinary.load(nil)
  end

  test "dump/1 and load/1 round-trip with non-trivial input" do
    input =
      %{foo: "bar"}
      |> Jason.encode!()

    assert {:ok, encoded} = EmbeddedBinary.dump(input)

    refute encoded == input

    assert {:ok, _encrypted} = Base.decode64(encoded)

    assert {:ok, decrypted} = EmbeddedBinary.load(encoded)

    assert decrypted == input
  end
end
