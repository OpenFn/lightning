defmodule Lightning.MetadataServiceTest do
  use Lightning.DataCase, async: false

  alias Lightning.MetadataService

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

      credential =
        insert(:credential)
        |> with_body(%{
          name: "main",
          body: %{
            "username" => "user",
            "password" => "pass",
            "host" => "https://example.com"
          }
        })

      assert MetadataService.fetch("@openfn/language-common", credential) ==
               {:ok, %{"foo" => "bar"}}
    end

    test "returns an error when the cli failed" do
      stdout = """
      {"level":"info","name":"CLI","message":["Metadata function found. Generating metadata..."]}
      """

      FakeRambo.Helpers.stub_run({:error, %{status: 1, out: stdout, err: ""}})

      credential =
        insert(:credential)
        |> with_body(%{
          name: "main",
          body: %{
            "username" => "user",
            "password" => "pass",
            "host" => "https://example.com"
          }
        })

      assert MetadataService.fetch("@openfn/language-common", credential) == {
               :error,
               %Lightning.MetadataService.Error{
                 type: "no_metadata_result",
                 __exception__: true
               }
             }
    end

    test "returns an error when the adaptor doesn't exist" do
      credential =
        insert(:credential)
        |> with_body(%{
          name: "main",
          body: %{
            "username" => "user",
            "password" => "pass",
            "host" => "https://example.com"
          }
        })

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

      credential =
        insert(:credential)
        |> with_body(%{
          name: "main",
          body: %{
            "username" => "user",
            "password" => "pass",
            "host" => "https://example.com"
          }
        })

      assert MetadataService.fetch("@openfn/language-common", credential) == {
               :error,
               %Lightning.MetadataService.Error{
                 type: "no_metadata_function",
                 __exception__: true
               }
             }
    end

    test "returns an error when the credential URL is not valid" do
      stdout = """
      {"level":"error","name":"CLI","message":["Exception while generating metadata"],"time":"1751622145724855949"}
      {"level":"error","name":"CLI","message":[{"request":{"transitional":{"silentJSONParsing":true,"forcedJSONParsing":true,"clarifyTimeoutError":false},"adapter":["xhr","http","fetch"],"transformRequest":[null],"transformResponse":[null],"timeout":0,"xsrfCookieName":"XSRF-TOKEN","xsrfHeaderName":"X-XSRF-TOKEN","maxContentLength":-1,"maxBodyLength":-1,"env":{},"headers":{"Accept":"application/json, text/plain, */*","Content-Type":"application/json","User-Agent":"axios/1.10.0","Accept-Encoding":"gzip, compress, deflate, br"},"url":"https://play.im.dhis2.org/stble-2-42-0/api/organisationUnits","responseType":"json","auth":"--REDACTED--","params":{"paging":false},"allowAbsoluteUrls":true,"method":"get"},"message":"Request failed with status code 404","response":"<html>\\r\\n<head><title>404 Not Found</title></head>\\r\\n<body>\\r\\n<center><h1>404 Not Found</h1></center>\\r\\n<hr><center>nginx</center>\\r\\n</body>\\r\\n</html>\\r\\n"}],"time":"1751622145725163375"}
      """

      FakeRambo.Helpers.stub_run({:ok, %{status: 0, out: stdout, err: ""}})

      credential =
        insert(:credential)
        |> with_body(%{
          name: "main",
          body: %{
            "username" => "user",
            "password" => "pass",
            "host" => "https://example.com"
          }
        })

      assert MetadataService.fetch("@openfn/language-common", credential) == {
               :error,
               %Lightning.MetadataService.Error{
                 type: "no_metadata_result",
                 __exception__: true
               }
             }
    end

    test "returns an error when the credentials are not valid" do
      stdout = """
      {"level":"error","name":"CLI","message":["Exception while generating metadata"],"time":"1751895555813622303"}
      {"level":"error","name":"CLI","message":[{"request":{"transitional":{"silentJSONParsing":true,"forcedJSONParsing":true,"clarifyTimeoutError":false},"adapter":["xhr","http","fetch"],"transformRequest":[null],"transformResponse":[null],"timeout":0,"xsrfCookieName":"XSRF-TOKEN","xsrfHeaderName":"X-XSRF-TOKEN","maxContentLength":-1,"maxBodyLength":-1,"env":{},"headers":{"Accept":"application/json, text/plain, */*","Conteient-Type":"application/json","User-Agent":"axios/1.10.0","Accept-Encoding":"gzip, compress, deflate, br"},"url":"https://play.im.dhis2.org/stable-2-42-0/api/organisationUnits","responseType":"json","auth":"--REDACTED--","params":{"paging":false},"allowAbsoluteUrls":true,"method":"get"},"message":"Request failed with status code 401","response":{"httpStatus":"Unauthorized","httpStatusCode":401,"status":"ERROR","message":"Unauthorized"}}],"time":"1751895555813789521"}
      """

      FakeRambo.Helpers.stub_run({:ok, %{status: 0, out: stdout, err: ""}})

      credential =
        insert(:credential)
        |> with_body(%{
          name: "main",
          body: %{
            "username" => "user",
            "password" => "pass",
            "host" => "https://example.com"
          }
        })

      assert MetadataService.fetch("@openfn/language-common", credential) == {
               :error,
               %Lightning.MetadataService.Error{
                 type: "no_metadata_result",
                 __exception__: true
               }
             }
    end
  end
end
