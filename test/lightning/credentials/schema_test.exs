defmodule Lightning.Credentials.SchemaTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Schema

  test "validate/2" do
    schema =
      """
      {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "properties": {
          "username": {
            "type": "string",
            "description": "The username used to log in"
          },
          "password": {
            "type": "string",
            "description": "The password used to log in",
            "writeOnly": true
          },
          "hostUrl": {
            "type": "string",
            "description": "The password used to log in",
            "format": "uri"
          }
        },
        "type": "object",
        "additionalProperties": true,
        "required": ["hostUrl", "password", "username"]
      }
      """
      |> Jason.decode!()
      |> ExJsonSchema.Schema.resolve()

    credential_body =
      """
      {
        "username": "foo",
        "password": "bar",
        "hostUrl": "fdgfdgd"
      }
      """
      |> Jason.decode!()

    changeset = %Ecto.Changeset{} = Schema.validate(schema, credential_body)

    assert {:hostUrl, ["Expected to be a URI"]} in errors_on(changeset)
  end
end
