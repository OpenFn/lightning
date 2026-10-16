defmodule LightningWeb.API.ProblemPaths do
  @moduledoc """
  The paths whose errors before a controller runs are problem documents: every
  `/api` route but the OAuth token endpoint, `/collections` and
  `/adaptors/catalogue` (error-format spec §1). Webhooks under `/i` answer their
  own.
  """

  @spec member?(Plug.Conn.t()) :: boolean()
  def member?(%Plug.Conn{path_info: path_info}), do: problem_path?(path_info)

  defp problem_path?(["api", "oauth", "token" | _]), do: false
  defp problem_path?(["api" | _]), do: true
  defp problem_path?(["collections" | _]), do: true
  defp problem_path?(["adaptors", "catalogue" | _]), do: true
  defp problem_path?(_path_info), do: false
end
