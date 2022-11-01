defmodule LightningWeb.JobLive.AdaptorsSetupComponent do
  @moduledoc """
  AdaptorsSetupComponent
  """

  use LightningWeb, :live_component

  alias LightningWeb.Components.Form

  @impl true
  def update(%{form: form, parent: parent}, socket) do
    {adaptor_name, _, adaptors, versions} =
      get_adaptor_version_options(Phoenix.HTML.Form.input_value(form, :adaptor))

    {:ok,
     socket
     |> assign(:adaptor_name, adaptor_name)
     |> assign(:adaptors, adaptors)
     |> assign(:versions, versions)
     |> assign(:parent, parent)
     |> assign(:form, form)}
  end

  def get_adaptor_version_options(adaptor) do
    # Gets @openfn/language-foo@1.2.3 or @openfn/language-foo

    adaptor_names =
      Lightning.AdaptorRegistry.all()
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.sort()

    {module_name, version, versions} =
      if adaptor do
        {module_name, version} =
          Lightning.AdaptorRegistry.resolve_package_name(adaptor)

        versions =
          Lightning.AdaptorRegistry.versions_for(module_name)
          |> List.wrap()
          |> Enum.map(&Map.get(&1, :version))
          |> Enum.sort_by(&Version.parse(&1), :desc)
          |> Enum.map(fn version ->
            [key: version, value: "#{module_name}@#{version}"]
          end)

        {module_name, version,
         [[key: "latest", value: "#{module_name}@latest"] | versions]}
      else
        {nil, nil, []}
      end

    {module_name, version, adaptor_names, versions}
  end

  @impl true
  def handle_event(
        "adaptor_name_change",
        %{"adaptor_component" => %{"adaptor_name" => adaptor_name}},
        socket
      ) do
    {mod, id} = socket.assigns.parent
    send_update(mod, id: id, adaptor: "#{adaptor_name}@latest")

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="md:col-span-2">
        <Form.label_field
          form={:adaptor_component}
          id={:adaptor_name}
          title="Adaptor"
          for="adaptorField"
        />
        <Form.select_field
          form={:adaptor_component}
          name={:adaptor_name}
          prompt=""
          selected={@adaptor_name}
          id="adaptorField"
          values={@adaptors}
          phx-change="adaptor_name_change"
          phx-target={@myself}
        />
      </div>

      <div class="md:col-span-2">
        <Components.Jobs.adaptor_version_select
          form={@form}
          adaptor_name={@adaptor_name}
          versions={@versions}
        />
      </div>
    </div>
    """
  end
end
