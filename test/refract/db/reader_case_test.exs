defmodule Refract.DB.ReaderCaseTest do
  use Refract.Test.ReaderCase,
    reader: Refract.DB,
    build: &Refract.DB.Fixture.lines!/2,
    load: false
end
