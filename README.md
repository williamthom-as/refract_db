# refract_db

database reader for [refract](https://github.com/williamthom-as/refract), through ecto.

- `Refract.DB.source/3` wraps a repo and a query (a schema, `{table, schema}` or any `Ecto.Query`)
- every reader tool works on it: `stream`, `locate`, `classify`, `suggest`, `profile`, `validate`
- pages follow a unique key (`key:`, default the schema's primary key), `paging: :offset` for an ordered query without one
- schema columns come back as ecto loads them, other columns as the adapter gives them
- `load`, `fields` and document rules need a sized source, so they are not available on a query
- reads and writes go through the repo's own functions, so a dynamic repo (`put_dynamic_repo/1`) is used
- `Refract.DB.shape/2` builds a shape from a schema: column names, a rule per type, `required:` and `aliases:` options
- `Refract.DB.insert/4` puts row maps into a schema's table: values cast by the field types, timestamps filled, chunked under the bind parameter limit, one transaction (`transaction: false` commits per chunk), upsert with ecto's `on_conflict:` / `conflict_target:`

```elixir
accounts = Refract.DB.source(MyApp.Repo, MyApp.Account)
{:ok, result} = Refract.DB.classify(accounts, shapes)
{:ok, report} = Refract.DB.validate(accounts, MyApp.Shapes.Account)
{:ok, rows} = Refract.DB.stream(accounts, page_size: 1_000)
{:ok, 1_204} = Refract.DB.insert(rows, MyApp.Repo, MyApp.Account)
shape = Refract.DB.shape(MyApp.Account, required: [:account_no], aliases: %{account_no: ["acct"]})
```

## Tests

sqlite always; postgres when reachable (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, default `postgres` / `postgres` on `localhost`, database `refract_db_test`), tagged `:postgres`; mysql when reachable (`MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`, default `root` / `mysql` on `127.0.0.1`, database `refract_db_test`), tagged `:mysql`; an unreachable server's tests are excluded, `REQUIRE_POSTGRES=true` / `REQUIRE_MYSQL=true` (ci) fail the run instead. the postgres suite drops and recreates its own `refract_db` schema, the mysql suite drops every table in its database.

## Install

```elixir
{:refract, path: "../refract"},
{:refract_db, path: "../refract_db"}
```
