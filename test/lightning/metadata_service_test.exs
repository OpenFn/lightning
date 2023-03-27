defmodule Lightning.MetadataServiceTest do
  use Lightning.DataCase, async: true

  alias Lightning.MetadataService
  import Lightning.CredentialsFixtures

  describe "fetch/2" do
    test "returns the metadata when it exists" do
      path = Temp.open!(%{suffix: ".json"}, &IO.write(&1, ~s({"foo": "bar"})))

      stdout = """
      {"message":["#{path}"]}
      """

      FakeRambo.Helpers.stub_run({:ok, %{status: 0, out: stdout, err: ""}})
      credential = credential_fixture()

      assert MetadataService.fetch("@openfn/language-common", credential) == %{
               "foo" => "bar"
             }
    end

    test "returns an error when the adaptor doesn't exist" do
      credential = credential_fixture()

      assert {:error, :no_matching_adaptor} ==
               MetadataService.fetch("@openfn/language-foo", credential)
    end

    test "returns an error when the cli failed" do
      credential = credential_fixture()

      assert MetadataService.fetch("@openfn/language-common", credential) ==
               {:error, :no_metadata_result}
    end
  end
end
