defmodule Refract.DB.Source do
  @moduledoc false

  import Ecto.Query, only: [order_by: 3]
  import Refract.DB.ArgValidator, only: [validate_repo!: 1]

  @enforce_keys [:repo, :query, :schema, :fields, :paging, :key, :key_column]

  defstruct [:repo, :query, :schema, :fields, :paging, :key, :key_column]

  @type paging :: :keyset | :offset

  @type t :: %__MODULE__{
          repo: module(),
          query: Ecto.Query.t(),
          schema: module() | nil,
          fields: %{String.t() => atom()},
          paging: paging(),
          key: atom() | nil,
          key_column: String.t() | nil
        }

  @type opt :: {:key, atom() | nil} | {:paging, paging()}

  @spec new(module(), Ecto.Queryable.t(), [opt()]) :: t()

  def new(repo, queryable, opts) do
    opts = Keyword.validate!(opts, key: nil, paging: :keyset)
    key = Keyword.fetch!(opts, :key)
    paging = Keyword.fetch!(opts, :paging)

    validate_repo!(repo)
    validate_key(key)
    validate_paging(paging)

    query = Ecto.Queryable.to_query(queryable)
    schema = schema(query)

    validate_select(query, schema)
    validate_unpaged(query)
    validate_order(query, paging)

    build(paging, repo, query, schema, key)
  end

  @spec table(t()) :: String.t() | nil

  def table(%__MODULE__{query: %Ecto.Query{from: %Ecto.Query.FromExpr{source: {table, _schema}}}})
      when is_binary(table),
      do: table

  def table(%__MODULE__{}), do: nil

  defp build(:offset, repo, query, schema, _key) do
    %__MODULE__{
      repo: repo,
      query: query,
      schema: schema,
      fields: fields(schema),
      paging: :offset,
      key: nil,
      key_column: nil
    }
  end

  defp build(:keyset, repo, query, schema, key) do
    key = key(schema, key)

    %__MODULE__{
      repo: repo,
      query: order_by(query, [q], asc: field(q, ^key)),
      schema: schema,
      fields: fields(schema),
      paging: :keyset,
      key: key,
      key_column: column(schema, key)
    }
  end

  defp schema(%Ecto.Query{from: %Ecto.Query.FromExpr{source: {_table, schema}}})
       when is_atom(schema),
       do: schema

  defp schema(_query), do: nil

  defp fields(nil), do: %{}

  defp fields(schema) do
    Map.new(
      schema.__schema__(:fields),
      &{Atom.to_string(schema.__schema__(:field_source, &1)), &1}
    )
  end

  defp key(nil, nil) do
    raise ArgumentError,
          "a schemaless query pages by a unique column, give key: or paging: :offset"
  end

  defp key(schema, nil), do: primary_key(schema.__schema__(:primary_key), schema)
  defp key(_schema, key), do: key

  defp primary_key([key], _schema), do: key

  defp primary_key(_keys, schema) do
    raise ArgumentError,
          "#{inspect(schema)} has no single column primary key, give key: or paging: :offset"
  end

  defp column(nil, key), do: Atom.to_string(key)
  defp column(schema, key), do: schema.__schema__(:field_source, key) |> column(schema, key)

  defp column(nil, schema, key) do
    raise ArgumentError, "key #{inspect(key)} is not a field of #{inspect(schema)}"
  end

  defp column(source, _schema, _key), do: Atom.to_string(source)

  defp validate_key(key) when is_atom(key), do: :ok

  defp validate_key(key) do
    raise ArgumentError, "key must be a field name atom, got: #{inspect(key)}"
  end

  defp validate_paging(paging) when paging in [:keyset, :offset], do: :ok

  defp validate_paging(paging) do
    raise ArgumentError, "paging must be :keyset or :offset, got: #{inspect(paging)}"
  end

  defp validate_select(%Ecto.Query{select: nil}, nil) do
    raise ArgumentError, "a schemaless query must select its columns"
  end

  defp validate_select(_query, _schema), do: :ok

  defp validate_unpaged(%Ecto.Query{limit: nil, offset: nil}), do: :ok

  defp validate_unpaged(_query) do
    raise ArgumentError, "the query is paged by the reader, drop its limit and offset"
  end

  defp validate_order(%Ecto.Query{order_bys: []}, :keyset), do: :ok

  defp validate_order(_query, :keyset) do
    raise ArgumentError,
          "a keyset paged query is ordered by its key, drop order_by or give paging: :offset"
  end

  defp validate_order(%Ecto.Query{order_bys: [_ | _]}, :offset), do: :ok

  defp validate_order(_query, :offset) do
    raise ArgumentError, "an offset paged query needs order_by, or pages can repeat or skip rows"
  end
end
