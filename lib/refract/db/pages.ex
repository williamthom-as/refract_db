defmodule Refract.DB.Pages do
  @moduledoc false

  import Ecto.Query, only: [limit: 3, offset: 3, where: 3]

  alias Refract.DB.Cells
  alias Refract.DB.Source

  @type cursor :: :start | {:after, term()} | non_neg_integer() | :done

  @spec lines(Refract.source(), pos_integer()) :: {:ok, Enumerable.t()} | {:error, term()}

  def lines(%Source{} = source, page_size) do
    cursor = first(source)

    with {:ok, %{columns: columns, rows: rows}} <- fetch(source, cursor, page_size),
         {:ok, position} <- key_position(source, columns) do
      lines = Cells.lines(source, columns, rows)
      next = after_page(source, position, page_size, cursor, rows, lines)

      {:ok,
       Stream.concat([
         [columns],
         lines,
         Stream.resource(
           fn -> next end,
           &page(source, columns, position, page_size, &1),
           fn _cursor -> :ok end
         )
       ])}
    end
  end

  def lines(source, _page_size), do: {:error, {:unsupported_source, source}}

  defp first(%Source{paging: :keyset}), do: :start
  defp first(%Source{paging: :offset}), do: 0

  defp page(_source, _columns, _position, _page_size, :done), do: {:halt, :done}

  defp page(source, columns, position, page_size, cursor) do
    {:ok, %{rows: rows}} = fetch(source, cursor, page_size)
    lines = Cells.lines(source, columns, rows)

    {lines, after_page(source, position, page_size, cursor, rows, lines)}
  end

  defp after_page(source, position, page_size, cursor, rows, lines) do
    {count, last} = source |> key_lines(rows, lines) |> counted_last()

    next_cursor(count == page_size, source, position, page_size, cursor, last)
  end

  defp key_lines(%Source{schema: nil}, rows, _lines), do: rows
  defp key_lines(%Source{}, _rows, lines), do: lines

  defp counted_last(lines),
    do: Enum.reduce(lines, {0, nil}, fn line, {count, _last} -> {count + 1, line} end)

  defp next_cursor(false, _source, _position, _page_size, _cursor, _last), do: :done

  defp next_cursor(true, %Source{paging: :keyset}, position, _page_size, _cursor, last),
    do: {:after, Enum.at(last, position)}

  defp next_cursor(true, %Source{paging: :offset}, _position, page_size, at, _last),
    do: at + page_size

  defp fetch(%Source{repo: repo} = source, cursor, page_size) do
    {sql, params} = repo.to_sql(:all, paged(source, cursor, page_size))

    repo.query(sql, params)
  end

  defp paged(%Source{paging: :keyset, query: query}, :start, page_size),
    do: limit(query, [], ^page_size)

  defp paged(%Source{paging: :keyset, query: query, key: key}, {:after, last}, page_size),
    do: query |> where([q], field(q, ^key) > ^last) |> limit([], ^page_size)

  defp paged(%Source{paging: :offset, query: query}, at, page_size),
    do: query |> limit([], ^page_size) |> offset([], ^at)

  defp key_position(%Source{paging: :offset}, _columns), do: {:ok, nil}

  defp key_position(%Source{key: key, key_column: column}, columns),
    do: columns |> Enum.find_index(&(&1 == column)) |> position(key)

  defp position(nil, key), do: {:error, {:key_not_selected, key}}
  defp position(index, _key), do: {:ok, index}
end
