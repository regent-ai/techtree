defmodule TechTree.Schema do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime_usec]
      import Ecto.Changeset
    end
  end
end
