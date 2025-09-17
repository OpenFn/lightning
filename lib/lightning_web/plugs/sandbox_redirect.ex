defmodule LightningWeb.Plugs.SandboxRedirect do
  @moduledoc """
  Redirects legacy project URLs to sandbox-aware URLs using 'main' as default sandbox.

  Transforms:
  /projects/abc123/w -> /projects/abc123/main/w
  /projects/abc123/history -> /projects/abc123/main/history
  etc.
  """
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    %{"project_id" => project_id} = conn.params

    remaining_path = extract_remaining_path(conn.path_info, project_id)

    redirect(conn, to: "/projects/#{project_id}/main#{remaining_path}")
  end

  defp extract_remaining_path(path_info, project_id) do
    case Enum.find_index(path_info, &(&1 == project_id)) do
      nil ->
        ""

      index ->
        path_info
        |> Enum.drop(index + 1)
        |> case do
          [] -> ""
          segments -> "/" <> Enum.join(segments, "/")
        end
    end
  end
end
