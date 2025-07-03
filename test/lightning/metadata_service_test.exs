defmodule Lightning.MetadataServiceTest do
  use Lightning.DataCase, async: false

  alias Lightning.MetadataService
  import Lightning.CredentialsFixtures

  describe "fetch/2" do
    test "returns the metadata when it exists" do
      path =
        Briefly.create!(extname: ".json")
        |> tap(fn path ->
          File.write!(path, ~s({"foo": "bar"}))
        end)

      stdout = """
      {"level":"debug","name":"CLI","message":["config hash: ","0c11f1bffdcb34f4832fea539604e55990f5b42f96a6142b18e0c1de98fef084"],"time":"1751556807184679728"}
      {"level":"debug","name":"CLI","message":["loading adaptor from","/app/priv/openfn/lib/node_modules/@openfn/language-http-7.0.0/dist/index.cjs"],"time":"1751556807185164761"}
      {"level":"info","name":"CLI","message":["Metadata function found. Generating metadata..."],"time":"1751556986984195830"}
      {"level":"success","name":"CLI","message":["Done!"],"time":"1751556989156386986"}
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
      stdout = """
      {"level":"debug","name":"CLI","message":["config hash: ","0c11f1bffdcb34f4832fea539604e55990f5b42f96a6142b18e0c1de98fef084"],"time":"1751556807184679728"}
      {"level":"debug","name":"CLI","message":["loading adaptor from","/app/priv/openfn/lib/node_modules/@openfn/language-http-7.0.0/dist/index.cjs"],"time":"1751556807185164761"}
      {"level":"error","name":"CLI","message":["No metadata helper found"],"time":"1751556807394005966"}
      """

      FakeRambo.Helpers.stub_run({:ok, %{status: 0, out: stdout, err: ""}})
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
