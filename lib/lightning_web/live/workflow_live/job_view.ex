defmodule LightningWeb.WorkflowLive.JobView do
  alias Lightning.Helpers
  use LightningWeb, :component

  import LightningWeb.WorkflowLive.Components

  alias Lightning.Credentials
  alias LightningWeb.Components.Tabbed
  alias LightningWeb.WorkflowLive.EditorPane

  attr :id, :string, required: true
  slot :top

  slot :inner_block, required: false

  slot :bottom

  slot :column do
    attr :class, :string, doc: "Extra CSS classes for the column"
  end

  def container(assigns) do
    ~H"""
    <div class="relative h-full flex bg-white" id={@id}>
      <div class="grow flex h-full flex-col">
        <div class="">
          <%= render_slot(@top) %>
        </div>
        <!-- 3 column wrapper -->
        <div
          class="grow flex h-5/6 gap-0 m-0 w-screen"
          phx-hook="CollapsiblePanel"
          id="collapsibles"
        >
          <%= render_slot(@inner_block) %>
        </div>
        <div class="flex p-2 justify-end">
          <%= render_slot(@bottom) %>
        </div>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true
  attr :class, :string, default: ""
  attr :id, :string, required: true

  defp column(assigns) do
    ~H"""
    <div id={@id} class={["flex-1 px-2 pt-2 collapsible-panel", @class]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :job, :map, required: true
  attr :form, :map, required: true, doc: "A form built from a job"
  attr :current_user, :map, required: true
  attr :project, :map, required: true
  attr :close_url, :any, required: true
  attr :socket, :any, required: true
  attr :follow_run_id, :any, default: nil
  attr :snapshot_date, :any, required: true
  attr :snapshot_version, :string, required: true

  slot :footer

  slot :collapsible_panel do
    attr :id, :string, required: true
    attr :panel_title, :string, required: true
    attr :class, :string, doc: "Extra CSS classes for the column"
  end

  def job_edit_view(assigns) do
    ~H"""
    <.container id={"job-edit-view-#{@job.id}"}>
      <:top>
        <div class="flex p-4 gap-6">
          <div class="flex items-baseline font-semibold">
            <span>
              <.icon
                name="hero-code-bracket-mini"
                class="w-4 h-4 mr-2 text-indigo-500"
              />
            </span>
            <%= @job.name %>
          </div>
          <.adaptor_block adaptor={@job.adaptor} />
          <.credential_block credential={
            fetch_credential(
              @form[:project_credential_id] && @form[:project_credential_id].value
            )
          } />
          <.snapshot_version_chip
            snapshot_date={@snapshot_date}
            version={@snapshot_version}
          />
          <div class="flex flex-grow items-center justify-end">
            <.link
              id={"close-job-edit-view-#{@job.id}"}
              patch={@close_url}
              phx-hook="ClosePanelViaEscape"
            >
              <Heroicons.x_mark class="w-6 h-6 text-gray-500 hover:text-gray-700
                hover:cursor-pointer" />
            </.link>
          </div>
        </div>
      </:top>
      <%= for slot <- @collapsible_panel do %>
        <.collapsible_panel
          id={slot[:id]}
          panel_title={slot[:panel_title]}
          class={"#{slot[:class]} h-full border border-l-0"}
        >
          <%= render_slot(slot) %>
        </.collapsible_panel>
      <% end %>
      <.collapsible_panel
        id="job-editor-panel"
        class="h-full border border-l-0"
        panel_title="Editor"
      >
        <.live_component
          module={EditorPane}
          id={"job-editor-pane-#{@job.id}"}
          form={@form}
          disabled={@snapshot_version != "latest"}
          class="h-full"
        />
      </.collapsible_panel>
      <.collapsible_panel id="output-logs" class="h-full border border-l-0">
        <:tabs>
          <Tabbed.tabs
            id="tab-bar-1"
            default_hash="run"
            class="flex flex-row space-x-6 -my-2 job-viewer-tabs"
          >
            <:tab hash="run">
              <span class="inline-block align-middle">Run</span>
            </:tab>
            <:tab hash="log">
              <span class="inline-block align-middle">Log</span>
            </:tab>
            <:tab hash="input">
              <span class="inline-block align-middle">Input</span>
            </:tab>
            <:tab hash="output">
              <span class="inline-block align-middle">Output</span>
            </:tab>
          </Tabbed.tabs>
        </:tabs>

        <%= if @follow_run_id do %>
          <%= live_render(
            @socket,
            LightningWeb.RunLive.RunViewerLive,
            id: "run-viewer-#{@follow_run_id}",
            session: %{
              "run_id" => @follow_run_id,
              "job_id" => @job.id,
              "project_id" => @project.id,
              "user_id" => @current_user.id
            },
            container: {:div, class: "h-full"}
          ) %>
        <% else %>
          <div class="w-1/2 h-16 text-center m-auto pt-4">
            <div class="text-gray-500 pb-2">
              After you click run, the logs and output will be visible here.
            </div>
          </div>
        <% end %>
      </.collapsible_panel>
      <:bottom>
        <%= render_slot(@footer) %>
      </:bottom>
    </.container>
    """
  end

  defp snapshot_version_chip(assigns) do
    ~H"""
    <div id="modal-header-workflow-snapshot-block" class="flex items-baseline">
      <span
        id="workflow-snapshot-version-chip"
        phx-hook="Tooltip"
        data-placement="bottom"
        aria-label={
          if @version == "latest",
            do: "This is the latest version of the workflow.",
            else:
              "You are viewing a snapshot of this workflow that was made on #{Helpers.format_date(@snapshot_date)}"
        }
        class={"inline-flex items-center rounded-md bg-#{if @version == "latest", do: "blue-100", else: "yellow-100"} px-2 py-1 text-xs font-medium text-#{if @version == "latest", do: "blue-800", else: "yellow-800"}"}
      >
        <% IO.inspect(@version) %>
        <%= if @version == "latest",
          do: @version,
          else: String.slice(@version, 1..7) %>
      </span>
    </div>
    """
  end

  defp credential_block(assigns) do
    ~H"""
    <div id="modal-header-credential-block" class="flex items-baseline">
      <%= if @credential do %>
        <Common.tooltip
          id="credential-name-tooltip"
          title={"Credential: " <> @credential.name}
          class="mr-2"
          icon_class="text-indigo-500 h-4 w-4"
          icon="hero-lock-closed-mini"
        />
        <span class="text-xs text-gray-500 font-semibold">
          <%= @credential.name %>
        </span>
      <% else %>
        <Common.tooltip
          id="credential-name-tooltip"
          title="This step doesn't use a credential."
          class="mr-2"
          icon_class="text-gray-500 h-4 w-4"
          icon="hero-lock-open-mini"
        />
        <span class="text-xs text-gray-500 font-semibold">
          No Credential
        </span>
      <% end %>
    </div>
    """
  end

  defp adaptor_block(assigns) do
    {package_name, version} =
      Lightning.AdaptorRegistry.resolve_package_name(assigns.adaptor)

    assigns =
      assigns
      |> assign(
        package_name: package_name,
        version: version
      )

    ~H"""
    <div id="modal-header-adaptor-block" class="flex items-baseline">
      <Common.tooltip
        id="adaptor-name-tooltip"
        title={"Adaptor: " <> @package_name <> "@" <> @version}
        class="mr-2"
        icon_class="text-indigo-500 h-4 w-4"
        icon="hero-cube-mini"
      />
      <code class="text-xs text-gray-500 font-semibold">
        <%= @package_name %>@<%= @version %>
      </code>
    </div>
    """
  end

  defp fetch_credential(project_credential_id) do
    project_credential_id && byte_size(project_credential_id) > 0 &&
      Credentials.get_credential_by_project_credential(project_credential_id)
  end
end
