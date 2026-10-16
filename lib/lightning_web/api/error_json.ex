defmodule LightningWeb.API.ErrorJSON do
  @moduledoc """
  The JSON view `render_errors` uses. On a path `LightningWeb.API.ProblemPaths`
  covers, a raise answers the problem document for its status; anywhere else it
  answers what `LightningWeb.ErrorView` does (error-format spec §5).
  """
  alias LightningWeb.API.Problem
  alias LightningWeb.API.ProblemPaths

  @codes %{
    400 => :malformed,
    403 => :forbidden,
    404 => :not_found,
    406 => :not_acceptable,
    413 => :too_large,
    415 => :unsupported_media_type,
    500 => :internal
  }

  def render(template, %{conn: conn, status: status} = assigns) do
    with true <- ProblemPaths.member?(conn),
         {:ok, code} <- Map.fetch(@codes, status) do
      Problem.body(Problem.new(code))
    else
      _ -> LightningWeb.ErrorView.render(template, assigns)
    end
  end
end
