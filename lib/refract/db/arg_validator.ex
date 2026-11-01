defmodule Refract.DB.ArgValidator do
  @moduledoc false

  @spec validate_timeout!(term()) :: :ok

  def validate_timeout!(:infinity), do: :ok
  def validate_timeout!(timeout) when is_integer(timeout) and timeout > 0, do: :ok

  def validate_timeout!(timeout) do
    raise ArgumentError,
          "timeout must be a positive integer or :infinity, got: #{inspect(timeout)}"
  end

  @spec validate_repo!(term()) :: :ok

  def validate_repo!(repo) when is_atom(repo),
    do: repo |> exports?(:__adapter__, 0) |> validate_repo!(repo)

  def validate_repo!(repo), do: invalid_repo(repo)

  defp validate_repo!(true, _repo), do: :ok
  defp validate_repo!(false, repo), do: invalid_repo(repo)

  defp invalid_repo(repo) do
    raise ArgumentError, "repo must be an ecto repo module, got: #{inspect(repo)}"
  end

  @spec validate_schema!(term()) :: :ok

  def validate_schema!({table, schema}) when is_binary(table), do: validate_schema!(schema)

  def validate_schema!(schema) when is_atom(schema),
    do: schema |> exports?(:__schema__, 1) |> validate_schema!(schema)

  def validate_schema!(schema), do: invalid_schema(schema)

  defp validate_schema!(true, _schema), do: :ok
  defp validate_schema!(false, schema), do: invalid_schema(schema)

  defp invalid_schema(schema) do
    raise ArgumentError,
          "schema must be an ecto schema module or {table, schema}, got: #{inspect(schema)}"
  end

  defp exports?(module, function, arity),
    do: Code.ensure_loaded?(module) and function_exported?(module, function, arity)
end
