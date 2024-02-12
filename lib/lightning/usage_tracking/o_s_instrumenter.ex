defmodule Lightning.UsageTracking.OSInstrumenter do
  @moduledoc """
  Provides OS details for Usagetracking submission.


  """
  def instrument(operating_system_name) do
    %{operating_system: operating_system_name}
    |> Map.merge(operating_system_detail(operating_system_name))
  end

  defp operating_system_detail("linux" = _operating_system_name) do
    case System.cmd("uname", ["-a"]) do
      {detail, 0} -> %{operating_system_detail: String.trim(detail)}
      _non_zero_response -> operating_system_detail(nil)
    end
  end

  defp operating_system_detail(_operating_system_name) do
    %{operating_system_detail: nil}
  end
end
