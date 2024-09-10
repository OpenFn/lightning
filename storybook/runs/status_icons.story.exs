defmodule LightningWeb.Storybook.Runs.StatusIcons do
  alias LightningWeb.RunLive.Components
  use PhoenixStorybook.Story, :component

  # required
  def function, do: &Components.step_icon/1

  def variations do
    [
      {:nothing, nil, nil},
      {:success, "success", nil},
      {:fail, "fail", nil},
      {:crash, "crash", nil},
      {:cancel, "cancel", nil},
      {:kill_security, "kill", "SecurityError"},
      {:kill_import, "kill", "ImportError"},
      {:kill_timeout, "kill", "TimeoutError"},
      {:kill_oom, "kill", "OOMError"},
      {:exception, "exception", ""},
      {:list, "lost", nil}
    ]
    |> Enum.map(fn {id, reason, error_type} ->
      %Variation{
        id: id,
        description: "Status Icon",
        attributes: %{reason: reason, error_type: error_type},
        slots: []
      }
    end)
  end
end
