library ieee;
use ieee.std_logic_1164.all;

library vunit_lib;
context vunit_lib.vunit_context;

package vunit_common_pkg is
  procedure clk_gen(signal clk : out std_logic; constant PERIOD : time);

  function str_to_slv(encoded_slv_string : string) return std_logic_vector;
end package vunit_common_pkg;

package body vunit_common_pkg is
  -- procedure for clock generation
  procedure clk_gen(signal clk : out std_logic; constant PERIOD : time) is
    constant HIGH_TIME : time := PERIOD / 2;
    constant LOW_TIME  : time := PERIOD - HIGH_TIME;
  begin
    assert (HIGH_TIME /= 0 fs) report "clk: frequency is too high" severity FAILURE;
    loop
      clk <= '1';
      wait for HIGH_TIME;
      clk <= '0';
      wait for LOW_TIME;
    end loop;
  end procedure;

  -- Decode a slv from a string. Valid characters are only '0' and '1'.
  function str_to_slv(encoded_slv_string : string) return std_logic_vector is
    variable slv : std_logic_vector(encoded_slv_string'length-1 downto 0);
  begin
    for i in encoded_slv_string'range loop
      case encoded_slv_string(i) is
        when '0' =>
          slv(i-1) := '0';
        when '1' =>
          slv(i-1) := '1';
        when others =>
          slv(i-1) := 'U';
      end case;
    end loop;
    return slv;
  end function str_to_slv;
end package body;
