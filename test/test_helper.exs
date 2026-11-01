alias Ecto.Adapters.SQL
alias Refract.DB.MyRepo
alias Refract.DB.PgRepo
alias Refract.DB.TestServer

{:ok, _repo} = Refract.DB.TestRepo.start_link(database: ":memory:", pool_size: 1, log: false)

postgres =
  TestServer.start(PgRepo, "REQUIRE_POSTGRES", fn repo ->
    SQL.query!(repo, "DROP SCHEMA IF EXISTS refract_db CASCADE")
    SQL.query!(repo, "CREATE SCHEMA refract_db")
  end)

mysql =
  TestServer.start(MyRepo, "REQUIRE_MYSQL", fn repo ->
    %{rows: rows} =
      SQL.query!(
        repo,
        "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE()"
      )

    Enum.each(rows, fn [table] -> SQL.query!(repo, "DROP TABLE `#{table}`") end)
  end)

excluded = for {tag, :unreachable} <- [postgres: postgres, mysql: mysql], do: tag

ExUnit.start(exclude: excluded)
