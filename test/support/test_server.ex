defmodule Refract.DB.TestServer do
  alias Ecto.Adapters.SQL

  def start(repo, required_env, reset) do
    repo
    |> reachable(reset)
    |> required(repo, required_env)
  end

  defp reachable(repo, reset) do
    with {:ok, _pid} <- repo.start_link(repo.options()),
         {:ok, _result} <- SQL.query(repo, "SELECT 1") do
      reset.(repo)
      :reachable
    else
      _unreachable ->
        if Process.whereis(repo), do: repo.stop()
        :unreachable
    end
  end

  defp required(:unreachable, repo, required_env) do
    if System.get_env(required_env) == "true" do
      raise "#{required_env} is set but #{inspect(repo)} is not reachable with " <>
              inspect(Keyword.delete(repo.options(), :password))
    end

    :unreachable
  end

  defp required(:reachable, _repo, _required_env), do: :reachable
end
