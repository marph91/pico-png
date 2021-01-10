package math_pkg is

  function min_int (l, r : integer) return integer;

end package math_pkg;

package body math_pkg is
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
