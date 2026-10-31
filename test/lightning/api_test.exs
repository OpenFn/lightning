defmodule Lightning.APITest do
  use ExUnit.Case, async: true

  @vsn Application.spec(:lightning, :vsn)

  describe "release/1" do
    test "drops a leading `v` from the image tag" do
      assert %{image_tag: "2.19.2"} =
               Lightning.API.release(image_tag: "v2.19.2")
    end

    test "leaves an image tag without a `v` unchanged" do
      assert %{image_tag: "2.19.2"} =
               Lightning.API.release(image_tag: "2.19.2")

      assert %{image_tag: "edge"} = Lightning.API.release(image_tag: "edge")
    end

    test "keeps a label set from outside, as Thunderbolt does" do
      assert %{label: "2.19.2 (1.4.0)", image_tag: "2.19.2", vsn: @vsn} =
               Lightning.API.release(
                 label: "2.19.2 (1.4.0)",
                 image_tag: "v2.19.2"
               )
    end

    test "fills in nil for keys that aren't set" do
      assert Lightning.API.release([]) == %{
               label: nil,
               commit: nil,
               image_tag: nil,
               branch: nil,
               vsn: @vsn
             }
    end
  end
end
