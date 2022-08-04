defmodule LightningWeb.CredentialLive.FormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.Credentials
  import Ecto.Changeset, only: [fetch_field!: 2, put_assoc: 3]
  import LightningWeb.Components.Form
  import LightningWeb.Components.Common

  @impl true
  def update(%{credential: credential, projects: projects} = assigns, socket) do
    changeset = Credentials.change_credential(credential)

    all_projects = projects |> Enum.map(&{&1.name, &1.id})

    schema = Credentials.Schema.new(fake_body_schema(), credential.body || %{})

    body_changeset = Credentials.Schema.changeset(schema, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       all_projects: all_projects,
       changeset: changeset,
       available_projects: filter_available_projects(changeset, all_projects),
       selected_project: "",
       schema: schema,
       body_changeset: body_changeset
     )}
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

  def input(form, field) do
    type = Phoenix.HTML.Form.input_type(form, field)
    apply(Phoenix.HTML.Form, type, [form, field])
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

    value = changeset |> Ecto.Changeset.get_field(field)

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

  @impl true
  def handle_event(
        "validate",
        %{"credential" => credential_params, "body" => body_params},
        socket
      ) do
    body_changeset =
      Lightning.Credentials.Schema.changeset(
        socket.assigns.schema,
        body_params
      )
      |> Map.put(:action, :validate)

    changeset =
      socket.assigns.credential
      |> Credentials.change_credential(credential_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(changeset: changeset, body_changeset: body_changeset)}
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
