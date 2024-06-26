library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.png_pkg.all;

entity adler32 is
  generic (
    C_INPUT_BITWIDTH : integer range 8 to 8 := 8
  );
  port (
    isl_clk   : in    std_logic;
    isl_start : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_INPUT_BITWIDTH - 1 downto 0);
    oslv_data : out   std_logic_vector(31 downto 0)
  );
end entity adler32;

architecture behavioral of adler32 is

  signal isl_valid_d1 : std_logic;
  signal islv_data_d1 : std_logic_vector(islv_data'range);

  type t_states is (CALC_S1, CALC_S2);

  signal state : t_states := CALC_S1;

  signal int_s1                     : integer range 0 to 2 ** 16 - 1;
  signal slv_current_adler_checksum : std_logic_vector(oslv_data'range) := (others => '0');

begin

  proc_adler32 : process (isl_clk) is

    variable v_data_in : std_logic_vector(islv_data'range);
    variable v_int_s2  : integer range 0 to 2 ** 16 - 1;
    variable v_sum1    : integer range 0 to 2 ** 17 - 1;
    variable v_sum2    : integer range 0 to 2 ** 17 - 1;

  begin

    if (rising_edge(isl_clk)) then
      assert C_INPUT_BITWIDTH mod 8 = 0;

      -- Adler checksum needs to be initialized first.
      -- TODO: Check this formally via PSL.
      assert not (isl_valid = '1' and isl_start = '1');
      if (isl_start = '1') then
        slv_current_adler_checksum <= x"00000001";
      end if;

      -- Incoming data can be processed every second cycle.
      assert not (isl_valid = '1' and isl_valid_d1 = '1');
      isl_valid_d1 <= isl_valid;
      islv_data_d1 <= islv_data;

      case state is

        when CALC_S1 =>

          if (isl_valid = '1') then
            v_data_in := islv_data;
            state     <= CALC_S2;
          elsif (isl_valid_d1 = '1') then
            v_data_in := islv_data_d1;
            state     <= CALC_S2;
          end if;

          v_sum1 := to_integer(unsigned(slv_current_adler_checksum(15 downto 0))) +
                    to_integer(unsigned(get_byte(v_data_in, 1)));

          -- Calculate the modulo manually, since it uses less resources and yields better timing.
          if (v_sum1 < 65521) then
            int_s1 <= v_sum1;
          else
            int_s1 <= v_sum1 - 65521;
          end if;

        when CALC_S2 =>

          v_sum2 := int_s1 + to_integer(unsigned(slv_current_adler_checksum(31 downto 16)));

          if (v_sum2 < 65521) then
            v_int_s2 := v_sum2;
          elsif (v_sum2 < 65521 * 2) then
            v_int_s2 := v_sum2 - 65521;
          else
            v_int_s2 := v_sum2 - 65521 * 2;
          end if;

          slv_current_adler_checksum <= std_logic_vector(to_unsigned(v_int_s2, 16)) &
                                        std_logic_vector(to_unsigned(int_s1, 16));
          state                      <= CALC_S1;

      end case;

    end if;

  end process proc_adler32;

  oslv_data <= slv_current_adler_checksum;

end architecture behavioral;
