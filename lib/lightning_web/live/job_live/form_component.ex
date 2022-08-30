defmodule LightningWeb.JobLive.FormComponent do
  @moduledoc """
  Macro for Form Components that edit and show Jobs.
  """
  import Ecto.Changeset, only: [get_field: 2]

  import Phoenix.LiveView,
    only: [assign: 2, assign: 3]

  alias Lightning.{
    Jobs,
    AdaptorRegistry,
    Projects,
    Workflows,
    Workflows.Workflow
  }

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

      def insert_workflow_id(params) do
        params["job"]["trigger"]["type"]
        |> case do
          n when n in ["webhook", "cron"] ->
            {:ok, %Workflow{id: workflow_id}} =
              Workflows.create_workflow(%{name: "workflow"})

            job_attrs =
              Map.get(params, "job")
              |> Map.put("workflow_id", workflow_id)

            %{"job" => job_attrs}

          n when n in ["success", "failure"] ->
            params
        end
      end

      @impl true
      def handle_event(event, params, socket) do
        params_with_workflow = insert_workflow_id(params)

        case event do
          "validate" ->
            {:noreply, validate(params_with_workflow, socket)}

          "save" ->
            {:noreply, save(params_with_workflow, socket)}
        end
      end

      import LightningWeb.JobLive.FormComponent
      defoverridable save: 2, validate: 2
    end
  end

  def update(%{job: job, project: project} = assigns, socket) do
    changeset = Jobs.change_job(job, %{"project_id" => job.project_id})

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

    upstream_jobs = Jobs.get_upstream_jobs_for(job)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:adaptor_name, adaptor_name)
     |> assign(:adaptors, adaptors)
     |> assign(:credentials, credentials)
     |> assign(:upstream_jobs, upstream_jobs)
     |> assign(:versions, versions)
     |> assign(:changeset, changeset)}
  end

  def validate(%{"job" => job_params}, socket) do
    job_params = coerce_params_for_adaptor_list(job_params)

    changeset =
      socket.assigns.job
      |> Jobs.change_job(job_params)
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
    get_field(changeset, :type) in [:on_job_failure, :on_job_success]
  end

  def requires_cron_job?(changeset) do
    get_field(changeset, :type) == :cron
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
