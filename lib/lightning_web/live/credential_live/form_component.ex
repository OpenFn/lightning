defmodule LightningWeb.CredentialLive.FormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.Credentials
  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3, get_field: 3]
  import LightningWeb.Components.Form
  import LightningWeb.Components.Common

  @impl true
  def update(%{credential: credential, projects: projects} = assigns, socket) do
    changeset = Credentials.change_credential(credential)

    all_projects = projects |> Enum.map(&{&1.name, &1.id})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       all_projects: all_projects,
       changeset: changeset,
       available_projects: filter_available_projects(changeset, all_projects),
       selected_project: "",
       schema: nil
     )
     |> assign_params_changes()
     |> assign_valid()}
  end

  defp fake_body_schema() do
    """
    {
      "$schema": "http://json-schema.org/draft-07/schema#",
      "properties": {
        "username": {
          "title": "Username",
          "type": "string",
          "description": "The username used to log in",
          "minLength": 1
        },
        "password": {
          "title": "Password",
          "type": "string",
          "description": "The password used to log in",
          "writeOnly": true,
          "minLength": 1
        },
        "hostUrl": {
          "title": "Host URL",
          "type": "string",
          "description": "The destination server Url",
          "format": "uri",
          "minLength": 1
        }
      },
      "type": "object",
      "additionalProperties": true,
      "required": ["hostUrl", "password", "username"]
    }
    """
    |> Jason.decode!()
  end

  def schema_input(schema_root, changeset, field) do
    # credential[project_credentials][0][project_id]
    properties =
      schema_root.schema
      |> Map.get("properties")
      |> Map.get(field |> to_string())

    text = properties |> Map.get("title")

    type =
      case properties do
        %{"format" => "uri"} -> :url_input
        %{"type" => "string", "writeOnly" => true} -> :password_input
        %{"type" => "string"} -> :text_input
      end

    value = changeset |> get_field(field, nil)

    [
      label(:body, field, text,
        class: "block text-sm font-medium text-secondary-700"
      ),
      Enum.map(
        Keyword.get_values(changeset.errors, field) |> Enum.slice(0..0),
        fn error ->
          content_tag(:span, translate_error(error),
            phx_feedback_for: input_name(:body, field)
          )
        end
      ),
      apply(Phoenix.HTML.Form, type, [
        :body,
        field,
        [
          value: value,
          class: ~w(mt-1 focus:ring-primary-500 focus:border-primary-500 block
               w-full shadow-sm sm:text-sm border-secondary-300 rounded-md)
        ]
      ])
    ]
  end

  defp assign_valid(socket) do
    socket
    |> assign(
      valid:
        case socket.assigns do
          %{changeset: changeset, schema_changeset: schema_changeset}
          when not is_nil(schema_changeset) ->
            changeset.valid? && schema_changeset.valid?

          %{changeset: changeset} ->
            changeset.valid?
        end
    )
  end

  defp assign_params_changes(socket, params \\ %{}) do
    %{changeset: changeset, schema: schema} = socket.assigns

    case {schema, params["credential"]["schema"]} do
      {_, "raw"} ->
        socket
        |> assign(
          schema: nil,
          schema_changeset: nil,
          changeset:
            create_changeset(
              socket.assigns.credential,
              params |> Map.get("credential")
            )
        )

      {nil, _schema_type} ->
        schema =
          Credentials.Schema.new(
            fake_body_schema(),
            changeset |> fetch_field!(:body) || %{}
          )

        schema_changeset = create_schema_changeset(schema, params)

        changeset =
          create_changeset(
            socket.assigns.credential,
            merge_schema_body(params["credential"], schema_changeset)
          )

        socket
        |> assign(
          schema: schema,
          schema_changeset: schema_changeset,
          changeset: changeset
        )

      {schema, _schema_type} ->
        schema_changeset = create_schema_changeset(schema, params)

        changeset =
          create_changeset(
            socket.assigns.credential,
            merge_schema_body(params["credential"], schema_changeset)
          )

        socket
        |> assign(schema_changeset: schema_changeset, changeset: changeset)
    end
  end

  defp merge_schema_body(nil, _schema_changeset), do: %{}

  defp merge_schema_body(params, schema_changeset) do
    schema_body = Ecto.Changeset.apply_changes(schema_changeset)
    Map.put(params, "body", schema_body)
  end

  defp create_schema_changeset(schema, params) do
    Credentials.Schema.changeset(schema, params |> Map.get("body", %{}))
    |> Map.put(:action, :validate)
  end

  defp create_changeset(credential, params) do
    credential
    |> Credentials.change_credential(params)
    |> Map.put(:action, :validate)
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign_params_changes(params)
     |> assign_valid()}
  end

  @impl true
  def handle_event(
        "select_item",
        %{"id" => project_id},
        socket
      ) do
    {:noreply, socket |> assign(selected_project: project_id)}
  end

  @impl true
  def handle_event(
        "add_new_project",
        %{"projectid" => project_id},
        socket
      ) do
    project_credentials =
      fetch_field!(socket.assigns.changeset, :project_credentials)

    project_credentials =
      Enum.find(project_credentials, fn pu -> pu.project_id == project_id end)
      |> if do
        project_credentials
        |> Enum.map(fn pu ->
          if pu.project_id == project_id do
            Ecto.Changeset.change(pu, %{delete: false})
          end
        end)
      else
        project_credentials
        |> Enum.concat([
          %Lightning.Projects.ProjectCredential{project_id: project_id}
        ])
      end

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_credentials, project_credentials)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(
       changeset: changeset,
       available_projects: available_projects,
       selected_project: ""
     )}
  end

  @impl true
  def handle_event("delete_project", %{"index" => index}, socket) do
    index = String.to_integer(index)

    project_credentials_params =
      fetch_field!(socket.assigns.changeset, :project_credentials)
      |> Enum.with_index()
      |> Enum.reduce([], fn {pu, i}, project_credentials ->
        if i == index do
          if is_nil(pu.id) do
            project_credentials
          else
            [Ecto.Changeset.change(pu, %{delete: true}) | project_credentials]
          end
        else
          [pu | project_credentials]
        end
      end)

    changeset =
      socket.assigns.changeset
      |> put_assoc(:project_credentials, project_credentials_params)
      |> Map.put(:action, :validate)

    available_projects =
      filter_available_projects(changeset, socket.assigns.all_projects)

    {:noreply,
     socket
     |> assign(changeset: changeset, available_projects: available_projects)}
  end

  def handle_event(
        "save",
        %{"credential" => credential_params, "body" => body_params},
        socket
      ) do
    save_credential(
      socket,
      socket.assigns.action,
      credential_params |> Map.put("body", body_params)
    )
  end

  def handle_event(
        "save",
        %{"credential" => credential_params},
        socket
      ) do
    save_credential(
      socket,
      socket.assigns.action,
      credential_params
    )
  end

  defp save_credential(socket, :edit, credential_params) do
    case Credentials.update_credential(
           socket.assigns.credential,
           credential_params
         ) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_credential(socket, :new, credential_params) do
    user_id = Ecto.Changeset.fetch_field!(socket.assigns.changeset, :user_id)

    credential_params
    # We are adding user_id in credential_params because we don't want to do it in the form
    |> Map.put("user_id", user_id)
    |> Credentials.create_credential()
    |> case do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp filter_available_projects(changeset, all_projects) do
    existing_ids =
      fetch_field!(changeset, :project_credentials)
      |> Enum.reject(fn pu -> pu.delete end)
      |> Enum.map(fn pu -> pu.credential_id end)

    all_projects
    |> Enum.reject(fn {_, credential_id} -> credential_id in existing_ids end)
  end
end
