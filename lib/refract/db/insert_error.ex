defmodule Refract.DB.InsertError do
  @moduledoc """
  raised by `Refract.DB.insert!/4` when a row cannot be inserted
  """

  defexception [:message]
end
