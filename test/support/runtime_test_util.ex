defmodule Lightning.Runtime.TestUtil do
  def fixture(name, type \\ :json) do
    path = "test/fixtures/#{Atom.to_string(name)}.#{type}"
    File.read!(path)
  end

  def run_spec_fixture(opts \\ []) do
    adaptor_path =
      Path.expand("./priv/openfn/lib/node_modules/@openfn/language-common")

    Lightning.Runtime.RunSpec.new(
      Enum.into(opts, %{
        expression_path: write_temp!(~s[alterState((state) => state)], ".js"),
        state_path: write_temp!(~s[{"foo": "bar"}], ".json"),
        adaptor: "@openfn/language-common=#{adaptor_path}",
        adaptors_path: "./priv/openfn/lib",
        final_state_path: Temp.path!(%{suffix: ".json"})
      })
    )
  end

  def timeout_expression(timeout) do
    ~s[
      alterState((state) => {
        console.log("Going on break for #{timeout}...")
        return new Promise(function(resolve, _reject) {
          setTimeout(resolve, #{timeout})
        });
      })
    ]
  end

  def write_temp!(contents, extension) do
    File.write!(path = Temp.path!(%{suffix: extension}), contents)
    path
  end
end
