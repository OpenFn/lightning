defmodule LightningWeb.CredentialLive.BodyForm do
  use LightningWeb, :live_component

  alias Lightning.Credentials

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="space-y-6 bg-white px-4 py-5 sm:p-6">
        <div :for={above <- @above} class={above[:class]}>
          <%= render_slot(above) %>
        </div>

        <div class="hidden sm:block" aria-hidden="true">
          <div class="border-t border-secondary-200"></div>
        </div>
        <fieldset>
          <legend class="contents text-base font-medium text-gray-900">
            Details
          </legend>
          <p class="text-sm text-gray-500">
            Configuration for this credential.
          </p>

          <div
            :for={
              body_form <-
                Phoenix.HTML.FormData.to_form(:credential, @form, :body,
                  default: @schema_changeset
                )
            }
            class="mt-4 space-y-4"
          >
            <div :for={{field, _type} <- @schema.types} class="grid grid-cols-2">
              <.schema_input form={body_form} schema={@schema} field={field} />
            </div>
          </div>
        </fieldset>

        <div :for={below <- @below} class={below[:class]}>
          <%= render_slot(below) %>
        </div>
      </div>

      <div class="bg-gray-50 px-4 py-3 sm:px-6">
        <div class="flex flex-rows">
          <div :for={button <- @button} class={button[:class]}>
            <%= render_slot(button, @valid?) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @valid_assigns [
    :below,
    :above,
    :button
  ]

  @impl true
  def update(%{form: form} = assigns, socket) do
    changeset = form.source

    {:ok,
     socket
     |> assign(
       changeset: changeset,
       schema: changeset |> Ecto.Changeset.get_field(:schema),
       form: form,
       schema_changeset: nil,
       input: [],
       valid?: false
     )
     |> assign(assigns |> filter_assigns(@valid_assigns))
     |> update(:schema, &get_schema/1)
     |> update(
       :schema_changeset,
       fn _, %{schema: schema, changeset: changeset} ->
         create_schema_changeset(
           schema,
           changeset |> Ecto.Changeset.get_field(:body) || %{}
         )
       end
     )
     |> update(
       :valid?,
       fn _,
          %{
            schema_changeset: schema_changeset,
            changeset: changeset
          } ->
         changeset.valid? and schema_changeset.valid?
       end
     )}
  end

  defp filter_assigns(assigns, keys) do
    assigns |> Map.filter(fn {k, _} -> k in keys end)
  end

  defp get_schema(schema_name) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    File.read!("#{schemas_path}/#{schema_name}.json")
    |> Jason.decode!()
    |> Credentials.Schema.new(schema_name)
  end

  defp create_schema_changeset(schema, params) do
    Credentials.SchemaDocument.changeset(%{}, params, schema: schema)
  end

  attr :form, :map, required: true
  attr :schema, :map, required: true
  attr :field, :any, required: true

  def schema_input(%{form: form, schema: schema, field: field} = assigns) do
    properties = Credentials.Schema.properties(schema, field)

    value = form.data |> Ecto.Changeset.get_field(field)
    errors = Keyword.get_values(form.data.errors, field)

    type =
      case properties do
        %{"format" => "uri"} -> :url_input
        %{"type" => "string", "writeOnly" => true} -> :password_input
        %{"type" => "string"} -> :text_input
        %{"type" => "integer"} -> :text_input
        %{"type" => "boolean"} -> :text_input
        %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]} -> :text_input
      end

    required = Credentials.Schema.required?(schema, field)

    assigns =
      assigns
      |> assign(
        value: value,
        errors: errors,
        title: properties |> Map.get("title"),
        required: required,
        type: type
      )

    ~H"""
    <LightningWeb.Components.Form.label_field
      form={@form}
      field={@field}
      title={@title}
    />
    <span :if={@required} class="text-sm text-secondary-700 text-right">
      Required
    </span>
    <div class="col-span-2">
      <%= apply(Phoenix.HTML.Form, @type, [
        @form,
        @field,
        [
          value: @value || "",
          class: ~w(mt-1 focus:ring-primary-500 focus:border-primary-500 block
               w-full shadow-sm sm:text-sm border-secondary-300 rounded-md)
        ]
      ]) %>
      <span
        :for={error <- @errors}
        phx-feedback_for={input_id(@form, @field)}
        class="block w-full text-sm text-secondary-700"
      >
        <%= translate_error(error) %>
      </span>
    </div>
    """
  end
end
