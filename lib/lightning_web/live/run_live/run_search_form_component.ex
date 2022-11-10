defmodule Lightning.RunLive.RunSearchFormComponent do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.RunSearchForm
  alias Lightning.RunSearchForm.RunStatusOption

  @run_statuses [
    %RunStatusOption{id: 1, label: "Success", selected: true},
    %RunStatusOption{id: 2, label: "Failure", selected: true},
    %RunStatusOption{id: 3, label: "Timeout", selected: true},
    %RunStatusOption{id: 3, label: "Crash", selected: true}
  ]


  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:run_search_changeset, fn -> build_search_changeset() end)
      |> assign(:run_statuses, @run_statuses)

    ~H"""
    <div>
      <.form :let={f} for={@run_search_changeset}>
        <.live_component
          id="run-status-select"
          module={Lightning.RunLive.RunStatusComponent}
          options={@run_statuses}
          form={f}
          on_selected={
            fn socket, statuses ->
              changeset = @run_search_changeset

              send(self(), {:search_updated, statuses})

              socket
                |> assign(
                  :run_search_changeset,
                  changeset
                  |> Ecto.Changeset.put_embed(:options, statuses)
                )

            end
          }
        />
      </.form>
    </div>
    """
  end

  def build_search_changeset() do
    %RunSearchForm{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(:options, @run_statuses)
  end
end
