# refract_db

database reader for [refract](https://github.com/williamthom-as/refract), through ecto.

- `Refract.DB.source/3` wraps a repo and a query (a schema, `{table, schema}` or any `Ecto.Query`)
- every reader tool works on it: `stream`, `locate`, `classify`, `suggest`, `profile`, `validate`
- pages follow a unique key (`key:`, default the schema's primary key), `paging: :offset` for an ordered query without one
- schema columns come back as ecto loads them, other columns as the adapter gives them
- `load`, `fields` and document rules need a sized source, so they are not available on a query
- `Refract.DB.insert/4` puts row maps into a schema's table: values cast by the field types, timestamps filled, chunked under the bind parameter limit, one transaction (`transaction: false` commits per chunk), upsert with ecto's `on_conflict:` / `conflict_target:`

```elixir
accounts = Refract.DB.source(MyApp.Repo, MyApp.Account)
{:ok, result} = Refract.DB.classify(accounts, shapes)
{:ok, report} = Refract.DB.validate(accounts, MyApp.Shapes.Account)
{:ok, rows} = Refract.DB.stream(accounts, page_size: 1_000)
{:ok, 1_204} = Refract.DB.insert(rows, MyApp.Repo, MyApp.Account)
```

## Install

```elixir
{:refract, path: "../refract"},
{:refract_db, path: "../refract_db"}
```
