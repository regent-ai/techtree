%{
  configs: [
    %{
      name: "default",
      strict: true,
      color: true,
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.PreferImplicitTry, []}
        ]
      }
    }
  ]
}
