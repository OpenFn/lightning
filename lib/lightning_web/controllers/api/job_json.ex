defmodule LightningWeb.API.JobJSON do
  @moduledoc false
  import LightningWeb.API.Helpers

  alias LightningWeb.Router.Helpers, as: Routes

  @fields ~w(name)a

  def render("index.json", %{page: page, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource(conn, &1)),
      included: [],
      links:
        %{
          self: url_for(conn)
        }
        |> Map.merge(pagination_links(conn, page))
    }
  end

  def render("show.json", %{job: job, conn: conn}) do
    %{
      data: resource(conn, job),
      included: [],
      links: %{
        self: url_for(conn)
      }
    }
  end

  defp resource(conn, job) do
    %{
      type: "jobs",
      relationships: %{},
      links: %{self: Routes.api_job_url(conn, :show, job)},
      id: job.id,
      attributes: Map.take(job, @fields)
    }
  end
end
