defmodule Refract.DB do
  @moduledoc """
  database reader and inserter for refract, through ecto. reads a query through its repo as
  lines: the selected column names, then a line per row, fetched a page at a time. pages follow a
  unique key (`key:`, default the schema's primary key), the key must be selected;
  `paging: :offset` pages an ordered query without one. a column of the query's schema comes back
  as ecto loads it (dates, decimals, booleans), any other column as the adapter gives it; maps and
  lists are their json text, other binaries lowercase hex.

  `insert/4` puts row maps into a schema's table: keys are field or column names, values cast by
  the field types (`""` is nil, as in a changeset), timestamps filled, in chunks under the bind
  parameter limit, in one transaction (`transaction: false` commits per chunk). an unknown column
  or a value that does not cast stops it, naming the row (from 1, as `Refract.Validate.rows/3`)
  and the column, never the value; a database error raises. upsert with ecto's own
  `on_conflict:` / `conflict_target:` (the count is what the adapter reports, mysql counts an
  updated row twice).

  `shape/2` builds a shape from a schema: a column per field under its column name (the field
  name an alias), generated keys and timestamps left out (`except:`), a rule from each type
  (integers, numbers, dates, datetimes, booleans, uuids, enum values). schemas do not say which
  columns are NOT NULL, `required:` names them: required in the header, `:required` in
  validation, and their type rules in row matching. `aliases:` adds header names per field.

      accounts = Refract.DB.source(MyApp.Repo, MyApp.Account)
      {:ok, result} = Refract.DB.classify(accounts, shapes)
      {:ok, report} = Refract.DB.validate(accounts, MyApp.Shapes.Account)
      {:ok, rows} = Refract.DB.stream(Refract.DB.source(MyApp.Repo, open_accounts), page_size: 1_000)
      {:ok, rows} = Refract.DB.stream(Refract.DB.source(MyApp.Repo, "ledger" |> select([l], map(l, [:entry_no, :amount])), key: :entry_no))
      {:ok, 1_204} = Refract.DB.insert(rows, MyApp.Repo, MyApp.Account)
      shape = Refract.DB.shape(MyApp.Account, required: [:account_no], aliases: %{account_no: ["acct"]})
      {:ok, 1_204} = Refract.DB.insert(rows, MyApp.Repo, MyApp.Account, on_conflict: {:replace_all_except, [:id, :inserted_at]}, conflict_target: [:id])
  """

  use Refract.Reader

  alias Refract.DB.FromSchema
  alias Refract.DB.Insert
  alias Refract.DB.InsertError
  alias Refract.DB.Pages
  alias Refract.DB.Source

  import Refract.ArgValidator, only: [validate_boolean!: 2, validate_positive_integer!: 2]
  import Refract.DB.ArgValidator

  @type open_opt :: {:page_size, pos_integer()}

  @type insert_opt ::
          {:chunk, pos_integer() | nil}
          | {:transaction, boolean()}
          | {:timeout, timeout()}
          | {:on_conflict, term()}
          | {:conflict_target, term()}

  @spec source(module(), Ecto.Queryable.t(), [Source.opt()]) :: Source.t()

  def source(repo, queryable, opts \\ []), do: Source.new(repo, queryable, opts)

  @spec indexing() :: :records

  @impl Refract.Reader
  def indexing, do: :records

  @spec open_options() :: keyword()

  @impl Refract.Reader
  def open_options, do: [page_size: 500]

  @spec open(Refract.source(), [open_opt()]) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl Refract.Reader
  def open(source, opts), do: Pages.lines(source, page_size!(opts))

  @spec facts(Refract.source(), [open_opt()]) :: {:ok, map()} | {:error, term()}

  @impl Refract.Reader
  def facts(source, opts), do: facts_of(source, page_size!(opts))

  @spec shape(module(), [FromSchema.opt()]) :: Refract.Shape.t()

  def shape(schema, opts \\ []), do: FromSchema.run(schema, opts)

  @spec insert(Enumerable.t(), module(), Insert.target(), [insert_opt()]) ::
          {:ok, non_neg_integer()} | {:error, Insert.error()}

  def insert(rows, repo, target, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        chunk: nil,
        transaction: true,
        timeout: :infinity,
        on_conflict: :raise,
        conflict_target: []
      )

    chunk = Keyword.fetch!(opts, :chunk)
    transaction = Keyword.fetch!(opts, :transaction)
    timeout = Keyword.fetch!(opts, :timeout)

    validate_repo!(repo)
    validate_schema!(target)
    validate_chunk(chunk)
    validate_boolean!(transaction, :transaction)
    validate_timeout!(timeout)

    Insert.run(rows, repo, target,
      chunk: chunk,
      transaction: transaction,
      timeout: timeout,
      insert_all: Keyword.take(opts, [:on_conflict, :conflict_target, :timeout])
    )
  end

  @spec insert!(Enumerable.t(), module(), Insert.target(), [insert_opt()]) :: non_neg_integer()

  def insert!(rows, repo, target, opts \\ []) do
    case insert(rows, repo, target, opts) do
      {:ok, count} ->
        count

      {:error, {reason, %{line: line, column: column}}} ->
        raise InsertError, message: "cannot insert rows: #{reason} line #{line}, #{column}"
    end
  end

  defp facts_of(%Source{schema: schema, paging: paging, key: key} = source, page_size) do
    {:ok,
     %{
       table: Source.table(source),
       schema: schema,
       paging: paging,
       key: key,
       page_size: page_size
     }}
  end

  defp facts_of(source, _page_size), do: {:error, {:unsupported_source, source}}

  defp page_size!(opts) do
    opts = Keyword.validate!(opts, open_options())
    page_size = Keyword.fetch!(opts, :page_size)

    validate_positive_integer!(page_size, :page_size)

    page_size
  end

  defp validate_chunk(nil), do: :ok
  defp validate_chunk(chunk), do: validate_positive_integer!(chunk, :chunk)
end
