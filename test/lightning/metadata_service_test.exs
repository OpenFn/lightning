defmodule Lightning.MetadataServiceTest do
  use Lightning.DataCase, async: false

  alias Lightning.MetadataService
  import Lightning.CredentialsFixtures

  describe "fetch/2" do
    # Now that MetadataService is run inside another process, the FakeRambo
    # test stub doesn't have access to the stubbed data.
    # Need to reconsider _how_ this is tested, or refactor the MetadataService,
    # TaskWorker and/or CLI module.
    @tag :skip
    test "returns the metadata when it exists" do
      path =
        Briefly.create!(extname: ".json")
        |> tap(fn path ->
          File.write!(path, ~s({"foo": "bar"}))
        end)

      stdout = """
      {"message":["#{path}"]}
      """

      FakeRambo.Helpers.stub_run({:ok, %{status: 0, out: stdout, err: ""}})
      credential = credential_fixture()

      assert MetadataService.fetch("@openfn/language-common", credential) ==
               {:ok,
                %{
                  "foo" => "bar"
                }}
    end

    @tag :skip
    test "returns an error when the cli failed" do
      stdout = """
      {"level":"info","name":"CLI","message":["Metadata function found. Generating metadata..."]}
      """

      FakeRambo.Helpers.stub_run({:error, %{status: 1, out: stdout, err: ""}})
      credential = credential_fixture()

      assert MetadataService.fetch("@openfn/language-common", credential) == {
               :error,
               %Lightning.MetadataService.Error{
                 type: "no_metadata_result",
                 __exception__: true
               }
             }
    end

    test "returns an error when the adaptor doesn't exist" do
      credential = credential_fixture()

      assert MetadataService.fetch("@openfn/language-foo", credential) == {
               :error,
               %Lightning.MetadataService.Error{
                 type: "no_matching_adaptor",
                 __exception__: true
               }
             }
    end

    test "returns an error when there's no magic yet for an adaptor" do
      credential = credential_fixture()

      assert MetadataService.fetch("@openfn/language-common", credential) == {
               :error,
               %Lightning.MetadataService.Error{
                 type: "no_metadata_function",
                 __exception__: true
               }
             }
    end
  end
end
