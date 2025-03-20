defmodule LightningWeb.DashboardLive.Components do
  use LightningWeb, :component

  import PetalComponents.Table

  alias LightningWeb.Components.Common
  alias Phoenix.LiveView.JS

  def welcome_banner(assigns) do
    ~H"""
    <div class="pb-6">
      <div class="flex justify-between items-center pt-6">
        <h1 class="text-2xl font-medium">
          Good day, {@user.first_name}!
        </h1>
        <button
          phx-click="toggle-welcome-banner"
          phx-target={@target}
          class="text-gray-500 focus:outline-none"
        >
          <span class="text-lg">
            <.icon name={"hero-chevron-#{if @collapsed, do: "up", else: "down"}"} />
          </span>
        </button>
      </div>

      <div
        id="welcome-banner-content"
        class={[
          "hover:overflow-visible transition-all duration-500 ease-in-out overflow-hidden",
          banner_content_classes(@collapsed)
        ]}
      >
        <p class="mb-6 mt-4">
          Here are some resources to help you get started with OpenFn
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          <%= for resource <- @resources do %>
            <.resource_card resource={resource} target={@target} />
          <% end %>
        </div>
      </div>

      <hr class="border-t border-gray-300 mt-4" />
      <.arcade_modal
        :if={@selected_resource}
        resource={@selected_resource}
        target={@id}
      />
    </div>
    """
  end

  defp resource_card(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="select-arcade-resource"
      phx-target={@target}
      phx-value-resource={@resource.id}
      class="relative flex items-end h-[150px] bg-gradient-to-r from-primary-800 to-primary-500 text-white rounded-lg shadow-xs hover:shadow-md transition-shadow duration-300 p-4 text-left"
    >
      <h2 class="text-lg font-semibold absolute bottom-4 left-4">
        {@resource.title}
      </h2>
    </button>
    """
  end

  defp arcade_modal(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal
        id={"arcade-modal-#{@resource.id}"}
        on_close={
          JS.push("modal_closed",
            value: %{id: "arcade-modal-#{@resource.id}"},
            target: "##{@target}"
          )
        }
        with_frame={false}
        show={true}
        width="w-5/6"
      >
        <div class="relative h-0 w-full pb-[60%]">
          <iframe
            src={@resource.link}
            title={@resource.title}
            frameborder="0"
            loading="lazy"
            webkitallowfullscreen
            mozallowfullscreen
            allowfullscreen
            allow="clipboard-write"
            style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; color-scheme: light;"
          >
          </iframe>
        </div>
        <div class="text-xs text-right text-gray-300 cursor-default mr-2">
          Voiceover generated by
          <a
            href="https://www.arcade.software/post/powered-by-ai-new-ways-to-enhance-your-demos-and-our-learnings-from-the-building-process"
            target="none"
            class="underline cursor-pointer"
          >
            Arcade AI
          </a>
        </div>
      </.modal>
    </div>
    """
  end

  defp banner_content_classes(collapsed) do
    case collapsed do
      true -> "max-h-0"
      false -> "max-h-[500px]"
      nil -> "max-h-[500px]"
    end
  end

  defp table_title(assigns) do
    ~H"""
    <h3 class="text-3xl font-bold">
      Projects
      <span class="text-base font-normal">
        ({@count})
      </span>
    </h3>
    """
  end

  def user_projects_table(assigns) do
    assigns =
      assign(assigns,
        projects_count: assigns.projects |> Enum.count(),
        empty?: assigns.projects |> Enum.empty?()
      )

    ~H"""
    <%= if @empty? do %>
      {render_slot(@empty_state)}
    <% else %>
      <div class="mt-5 flex justify-between mb-3">
        <.table_title count={@projects_count} />
        <div>
          {render_slot(@create_project_button)}
        </div>
      </div>
      <div id="projects-table">
        <.table>
          <.tr>
            <.th>
              <.sortable_table_header
                target_sort_key="name"
                current_sort_key={@sort_key}
                current_sort_direction={@sort_direction}
                target={@target}
              >
                Name
              </.sortable_table_header>
            </.th>
            <.th>Role</.th>
            <.th>Workflows</.th>
            <.th>Collaborators</.th>
            <.th>
              <.sortable_table_header
                target_sort_key="last_updated_at"
                current_sort_key={@sort_key}
                current_sort_direction={@sort_direction}
                target={@target}
              >
                Last Updated
              </.sortable_table_header>
            </.th>
            <.th></.th>
          </.tr>

          <.tr
            :for={project <- @projects}
            id={"projects-table-row-#{project.id}"}
            class="hover:bg-gray-100 transition-colors duration-200 cursor-pointer"
            phx-click={JS.navigate(~p"/projects/#{project.id}/w")}
          >
            <.td>
              {project.name}
            </.td>
            <.td class="break-words max-w-[25rem]">
              {project.role
              |> Atom.to_string()
              |> String.capitalize()}
            </.td>
            <.td class="break-words max-w-[10rem]">
              {project.workflows_count}
            </.td>
            <.td class="break-words max-w-[5rem]">
              <.link
                class="link"
                href={~p"/projects/#{project.id}/settings#collaboration"}
                onclick="event.stopPropagation()"
              >
                {project.collaborators_count}
              </.link>
            </.td>
            <.td>
              <%= if project.last_updated_at do %>
                {Lightning.Helpers.format_date(project.last_updated_at)}
              <% else %>
                N/A
              <% end %>
            </.td>
            <.td class="text-right">
              <.link
                class="table-action"
                navigate={~p"/projects/#{project.id}/history"}
                onclick="event.stopPropagation()"
              >
                History
              </.link>
            </.td>
          </.tr>
        </.table>
      </div>
    <% end %>
    """
  end

  attr :current_sort_key, :string, required: true
  attr :current_sort_direction, :string, required: true
  attr :target, :any, required: true
  attr :target_sort_key, :string, required: true
  slot :inner_block, required: true

  defp sortable_table_header(assigns) do
    ~H"""
    <Common.sortable_table_header
      phx-click="sort"
      phx-value-by={@target_sort_key}
      phx-target={@target}
      active={@current_sort_key == @target_sort_key}
      sort_direction={@current_sort_direction}
    >
      {render_slot(@inner_block)}
    </Common.sortable_table_header>
    """
  end
end
