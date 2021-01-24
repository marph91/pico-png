package math_pkg is

  function log2 (x : integer) return integer;

  function min_int (l, r : integer) return integer;

end package math_pkg;

package body math_pkg is
  -- compute the binary logarithm

  function log2 (x : integer) return integer is
    variable i : integer;
  begin
    i := 0;
    while 2 ** i < x loop
      i := i + 1;
    end loop;
    return i;
  end function log2;

  -- chose the minimum of two integer

  function min_int (l, r : integer) return integer is
  begin

    if (l < r) then
      return l;
    else
      return r;
    end if;

  end min_int;

end math_pkg;
