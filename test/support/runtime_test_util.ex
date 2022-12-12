defmodule Lightning.Runtime.TestUtil do
  def fixture(name, type \\ :json) do
    path = "test/fixtures/#{Atom.to_string(name)}.#{type}"
    File.read!(path)
  end

  def run_spec_fixture(opts \\ []) do
    Lightning.Runtime.RunSpec
    |> struct!(
      Enum.into(opts, %{
        expression_path: write_temp!(~s[alterState((state) => state)]),
        state_path: write_temp!(~s[{"foo": "bar"}]),
        adaptor: "@openfn/language-common",
        adaptors_path: "./priv/openfn",
        final_state_path: Temp.path!()
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

  def write_temp!(contents) do
    File.write!(path = Temp.path!(), contents)
    path
  end
end
