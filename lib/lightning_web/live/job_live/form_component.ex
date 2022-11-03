defmodule LightningWeb.JobLive.FormComponent do
  @moduledoc """
  Macro for Form Components that edit and show Jobs.
  """
  import Ecto.Changeset, only: [get_field: 2]

  import Phoenix.Component,
    only: [assign: 2, assign: 3]

  alias Lightning.{Jobs, AdaptorRegistry, Projects}
  alias Jobs.JobForm

  defmacro __using__(_opts) do
    quote do
      @behaviour LightningWeb.JobLive.FormComponent
      use LightningWeb, :live_component

      alias LightningWeb.Components.Form
      alias Lightning.{Jobs, AdaptorRegistry, Projects}

      @impl true
      defdelegate update(assigns, socket), to: LightningWeb.JobLive.FormComponent

      @impl true
      defdelegate save(params, socket), to: LightningWeb.JobLive.FormComponent

      @impl true
      defdelegate validate(params, socket),
        to: LightningWeb.JobLive.FormComponent

      def handle_event("job_body_changed", %{"source" => source}, socket) do
        {:noreply, socket |> assign(job_body: source)}
      end

      @impl true
      def handle_event(event, params, socket) do
        case event do
          "validate" ->
            {:noreply, validate(params, socket)}

          "save" ->
            {:noreply, save(params, socket)}
        end
      end

      import LightningWeb.JobLive.FormComponent
      defoverridable save: 2, validate: 2
    end
  end

  def update(
        %{
          job_form: job_form,
          project: project,
          initial_job_params: initial_job_params
        } = assigns,
        socket
      ) do
    changeset = JobForm.changeset(job_form, initial_job_params)

    {adaptor_name, _, adaptors, versions} =
      get_adaptor_version_options(
        changeset
        |> Ecto.Changeset.fetch_field!(:adaptor)
      )

    credentials =
      Projects.list_project_credentials(project)
      |> Enum.map(fn pu ->
        {pu.credential.name, pu.id}
      end)

    upstream_jobs = Jobs.get_upstream_jobs_for(job_form)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:adaptor_name, adaptor_name)
     |> assign(:adaptors, adaptors)
     |> assign(:credentials, credentials)
     |> assign(:upstream_jobs, upstream_jobs)
     |> assign(:versions, versions)
     |> assign(:job_form, job_form)
     |> assign(:job_body, job_form.body)
     |> assign(:changeset, changeset)
     |> assign(:job_params, %{})}
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

  def save(_params, _socket) do
    raise "save/2 not implemented"
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

  @doc """
  Coerce any changes to the "Adaptor" dropdown into a new selection on the
  Version dropdown.
  """
  @spec coerce_params_for_adaptor_list(%{String.t() => String.t()}) ::
          %{}
  def coerce_params_for_adaptor_list(job_params) do
    {package, _version} =
      AdaptorRegistry.resolve_package_name(job_params["adaptor"])

    {package_group, _} =
      AdaptorRegistry.resolve_package_name(job_params["adaptor_name"])

    cond do
      is_nil(package_group) ->
        Map.merge(job_params, %{"adaptor" => ""})

      package_group !== package ->
        Map.merge(job_params, %{"adaptor" => "#{package_group}@latest"})

      true ->
        job_params
    end
  end

  def requires_upstream_job?(changeset) do
    get_field(changeset, :trigger_type) in [:on_job_failure, :on_job_success]
  end

  def requires_cron_job?(changeset) do
    get_field(changeset, :trigger_type) == :cron
  end

  @callback save(
              job_params :: Phoenix.LiveView.unsigned_params(),
              socket :: Phoenix.LiveView.Socket.t()
            ) :: Phoenix.LiveView.Socket.t()

  @callback validate(
              job_params :: Phoenix.LiveView.unsigned_params(),
              socket :: Phoenix.LiveView.Socket.t()
            ) :: Phoenix.LiveView.Socket.t()
end
