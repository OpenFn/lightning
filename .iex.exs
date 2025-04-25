if Code.loaded?(Ecto.Query) do
  Kernel.SpecialForms.import(Ecto.Query)
end

alias Lightning.Repo
