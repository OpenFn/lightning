defmodule LightningWeb.API.RunStepJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  @fields ~w(job_id exit_reason error_type started_at finished_at input_dataclip_id output_dataclip_id)a

  def render("index.json", %{steps: steps, conn: conn}) do
    %{
      data: Enum.map(steps, &resource/1),
      included: [],
      links: %{self: self_url(conn)}
    }
  end

  defp resource(step) do
    %{
      type: "steps",
      id: step.id,
      attributes: Map.take(step, @fields),
      relationships: %{},
      links: %{}
    }
  end
end
