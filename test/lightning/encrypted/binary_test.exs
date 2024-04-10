defmodule Lightning.Encrypted.BinaryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Encrypted.Binary

  test "dump/1 with nil input" do
    assert {:ok, nil} = Binary.dump(nil)
  end

  test "load/1 with nil input" do
    assert {:ok, nil} = Binary.load(nil)
  end

  test "dump/1 and load/1 round-trip with non-trivial input" do
    input =
      %{foo: "bar"}
      |> Jason.encode!()

    assert {:ok, encoded} = Binary.dump(input)

    refute encoded == input

    assert {:ok, _encrypted} = Base.decode64(encoded)

    assert {:ok, decrypted} = Binary.load(encoded)

    assert decrypted == input
  end
end
