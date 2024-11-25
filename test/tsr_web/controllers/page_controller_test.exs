defmodule TsrWeb.PageControllerTest do
  use TsrWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Welcome to"
  end
end
