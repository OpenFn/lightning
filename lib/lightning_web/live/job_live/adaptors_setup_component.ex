defmodule LightningWeb.JobLive.AdaptorsSetupComponent do
  @moduledoc """
  AdaptorsSetupComponent
  """

  use LightningWeb, :live_component

  alias Lightning.Jobs.JobForm

  def update(
        %{
          form: form
        } = assigns,
        socket
      ) do
    changeset = JobForm.changeset(form)

    {adaptor_name, _, adaptors, versions} =
      get_adaptor_version_options(
        changeset
        |> Ecto.Changeset.fetch_field!(:adaptor)
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:adaptor_name, adaptor_name)
     |> assign(:adaptors, adaptors)
     |> assign(:changeset, changeset)}
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

  def validate(%{"job_form" => job_params}, socket) do
    job_params = coerce_params_for_adaptor_list(job_params)

    changeset =
      JobForm.changeset(socket.assigns.job_form, job_params)
      |> Map.put(:action, :validate)

    {adaptor_name, _, adaptors, versions} =
      get_adaptor_version_options(
        changeset
        |> Ecto.Changeset.fetch_field!(:adaptor)
      )

    assign(socket, :changeset, changeset)
    |> assign(:adaptor_name, adaptor_name)
    |> assign(:adaptors, adaptors)
    |> assign(:versions, versions)
    |> assign(:job_params, job_params)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="md:col-span-1">
        <Components.Jobs.adaptor_name_select
          form={@form}
          adaptor_name={@adaptor_name}
          adaptors={@adaptors}
        />
      </div>

      <div class="md:col-span-1">
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
