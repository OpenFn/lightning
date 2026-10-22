defmodule LightningWeb.Components.Viewers do
  @moduledoc """
  Components for rendering Logs and Dataclips.

  > #### Scrolling can be tricky {: .info}
  >
  > We seldom know how long a log or a dataclip will be, and we want to
  > be able to contain the element in a fixed height container.
  > In some situations wrapping the component in a `div` with `inline-flex`
  > class will help with scrolling.
  """

  use LightningWeb, :component

  import React

  alias Lightning.Invocation.Dataclip

  require Lightning.Run

  attr :id, :string, required: true
  attr :dataclipId, :map, required: true

  # react imports
  jsx("assets/js/react/components/DataclipViewer.tsx")

  def dataclip_viewer(assigns) do
    ~H"""
    <.DataclipViewer id={@id} dataclipId={@dataclip.id} />
    """
  end

  attr :id, :string, required: true
  attr :json, :string, required: true

  # react imports
  jsx("assets/js/react/components/CollectionPreviewViewer.tsx")

  def collection_preview_viewer(assigns) do
    ~H"""
    <.CollectionPreviewViewer id={@id} json={@json} />
    """
  end

  attr :id, :string, required: true

  attr :run_state, :any, required: true

  attr :class, :string,
    default: nil,
    doc: "Additional classes to add to the log viewer container"

  attr :step, :map
  attr :dataclip, Dataclip
  attr :input_or_output, :atom, required: true, values: [:input, :output]
  attr :project_id, :string, required: true

  attr :admin_contacts, :list,
    required: true,
    doc: "list of project admin emails"

  attr :can_edit_data_retention, :boolean, required: true

  def step_dataclip_viewer(assigns) do
    ~H"""
    <%= if dataclip_wiped?(@step, @dataclip, @input_or_output) do %>
      <.wiped_data_viewer
        id={@id}
        can_edit_data_retention={@can_edit_data_retention}
        admin_contacts={@admin_contacts}
        data_label={@input_or_output}
        project_id={@project_id}
      />
    <% else %>
      <div
        :if={
          @run_state in Lightning.Run.final_states() and
            is_nil(@dataclip)
        }
        class={[
          "m-2 relative rounded-md",
          "p-12 text-center col-span-full"
        ]}
      >
        <span class="relative inline-flex">
          <div class="inline-flex">
            No {@input_or_output} state could be saved for this run.
          </div>
        </span>
      </div>

      <div
        :if={
          @run_state not in Lightning.Run.final_states() and
            is_nil(@dataclip)
        }
        id={"#{@id}-nothing-yet"}
        class="relative rounded-md text-xs @md:text-base p-12 text-center bg-slate-700 font-mono text-gray-200"
      >
        <.text_ping_loader>
          Nothing yet
        </.text_ping_loader>
      </div>

      <.dataclip_viewer
        :if={@dataclip}
        id={"step-#{@input_or_output}-dataclip-viewer"}
        dataclip={@dataclip}
      />
    <% end %>
    """
  end

  attr :id, :string, default: nil

  attr :data_label, :atom,
    required: true,
    values: [:input, :output, :request_response]

  attr :project_id, :string, required: true

  attr :admin_contacts, :list,
    required: true,
    doc: "list of project admin emails"

  attr :can_edit_data_retention, :boolean, required: true

  slot :footer

  def wiped_data_viewer(assigns) do
    ~H"""
    <div
      id={@id}
      class="border-2 border-gray-200 border-dashed rounded-lg px-8 pt-6 pb-8 mb-4 flex flex-col"
    >
      <div class="mb-4">
        <div class="h-12 w-12 border-2 border-gray-300 border-solid mx-auto flex items-center justify-center rounded-full text-gray-400">
          <Heroicons.code_bracket class="w-4 h-4" />
        </div>
      </div>
      <div class="text-center mb-4 text-gray-500">
        <h3 class="font-bold text-lg">
          No {wiped_label(@data_label)} Data here!
        </h3>
        <p class="text-sm">
          {wiped_label(@data_label)} data for this {wiped_subject(@data_label)} has not been retained in accordance
          with your project's data storage policy.
        </p>
      </div>
      <div class="text-center text-gray-500 text-sm">
        <%= if @can_edit_data_retention do %>
          <%= if @data_label == :request_response do %>
            You can change
            <.link
              navigate={~p"/projects/#{@project_id}/settings#data-storage"}
              class="link"
            >
              this policy
            </.link>
            for future requests.
          <% else %>
            You can’t rerun this work order, but you can change
            <.link
              navigate={~p"/projects/#{@project_id}/settings#data-storage"}
              class="link"
            >
              this policy
            </.link>
            for future runs.
          <% end %>
        <% else %>
          Contact one of your
          <span
            id={"zero-persistence-admins-tooltip-#{@id}"}
            phx-hook="Tooltip"
            class="link inline-block"
            aria-label={Enum.join(@admin_contacts, ", ")}
          >
            project admins
          </span>
          for more information.
        <% end %>
      </div>
      {render_slot(@footer)}
    </div>
    """
  end

  defp step_finished?(%{finished_at: %_{}}), do: true

  defp step_finished?(_other), do: false

  defp dataclip_wiped?(_step, %{wiped_at: %_{}} = _dataclip, _input_or_output) do
    true
  end

  defp dataclip_wiped?(step, _dataclip, input_or_output) do
    dataclip_field = dataclip_field(input_or_output)

    step_finished?(step) and is_nil(Map.fetch!(step, dataclip_field))
  end

  defp dataclip_field(:input), do: :input_dataclip_id
  defp dataclip_field(:output), do: :output_dataclip_id

  defp wiped_label(:input), do: "Input"
  defp wiped_label(:output), do: "Output"
  defp wiped_label(:request_response), do: "Request/Response"

  defp wiped_subject(:input), do: "step"
  defp wiped_subject(:output), do: "step"
  defp wiped_subject(:request_response), do: "channel request"
end
