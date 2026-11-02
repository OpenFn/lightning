defmodule LightningWeb.API.WorkflowTemplateJSON do
  @moduledoc """
  JSON views for workflow templates. `code` is the workflow as v2 YAML.
  """
  import LightningWeb.API.Helpers

  alias Lightning.Workflows.WorkflowTemplate

  def index(%{page: page, filters: filters, conn: conn}) do
    %{
      data: Enum.map(page.entries, &template/1),
      links: pagination_links(conn, page, filters)
    }
  end

  def show(%{template: template}), do: %{template: template(template)}

  defp template(%WorkflowTemplate{} = template) do
    Map.take(template, [:id, :name, :description, :tags, :workflow_id, :code])
  end
end
