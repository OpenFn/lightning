defmodule LightningWeb.CredentialLive.RawBodyComponent do
  use LightningWeb, :component

  attr :form, :map, required: true
  attr :current_body, :map, default: %{}
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source
    assigns = assigns |> assign(valid?: changeset.valid?)

    ~H"""
    {render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &inner/1,
         [form: @form, current_body: @current_body],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    )}
    """
  end

  defp inner(%{current_body: current_body} = assigns) do
    {body_json, json_error} =
      cond do
        is_binary(current_body) and String.trim(current_body) != "" ->
          case Jason.decode(current_body) do
            {:ok, _decoded} ->
              {current_body, nil}

            {:error, _} ->
              {current_body, "Invalid JSON format. Please fix the syntax."}
          end

        is_map(current_body) ->
          {Jason.encode!(current_body, pretty: true), nil}

        true ->
          {"", nil}
      end

    errors = if json_error, do: [json_error], else: []

    assigns = assign(assigns, body_json: body_json, errors: errors)

    ~H"""
    <fieldset>
      <.input
        type="codearea"
        id={@form[:body].id}
        name={@form[:body].name}
        value={@body_json}
        label="Credential Body"
        required={true}
        errors={@errors}
      />
    </fieldset>
    """
  end
end
