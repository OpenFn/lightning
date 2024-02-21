defmodule Lightning.UsageTracking.OSInstrumenterTest do
  use ExUnit.Case
  import Mock

  alias Lightning.UsageTracking.OSInstrumenter

  test "returns OS name with nil details if OS is not linux" do
    operating_system_name = "not-linux"

    assert(
      %{
        operating_system: ^operating_system_name,
        operating_system_detail: nil
      } = OSInstrumenter.instrument(operating_system_name)
    )
  end

  test "returns extra detail if OS is linux" do
    operating_system_name = "linux"
    expected_detail = "Fedora blah"

    with_mock System,
      cmd: fn "uname", ["-a"] -> {expected_detail, 0} end do
      assert(
        %{
          operating_system: ^operating_system_name,
          operating_system_detail: ^expected_detail
        } = OSInstrumenter.instrument(operating_system_name)
      )
    end
  end

  test "returns nil detail if lookup fials for linux" do
    operating_system_name = "linux"

    with_mock System,
      cmd: fn "uname", ["-a"] -> {"does not matter", 1} end do
      assert(
        %{
          operating_system: ^operating_system_name,
          operating_system_detail: nil
        } = OSInstrumenter.instrument(operating_system_name)
      )
    end
  end

  test "integration test for linux that only runs on linux" do
    if :os.type() |> elem(1) == :linux do
      operating_system_name = "linux"

      {uname_output, 0} = System.cmd("uname", ["-a"])

      expected_detail = uname_output |> String.trim()

      assert String.match?(expected_detail, ~r/Linux/)

      assert(
        %{
          operating_system: ^operating_system_name,
          operating_system_detail: ^expected_detail
        } = OSInstrumenter.instrument(operating_system_name)
      )
    end
  end
end
