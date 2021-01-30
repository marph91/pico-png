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
    oslv_data : out   std_logic_vector(31 downto 0);
    osl_ready : out   std_logic
  );
end entity adler32;

architecture behavioral of adler32 is

  signal slv_data_in : std_logic_vector(C_INPUT_BITWIDTH - 1 downto 0) := (others => '0');

  type t_states is (IDLE, CALC_S1, CALC_S2, SEND_OUTPUT);

  signal state : t_states := IDLE;

  signal int_s1                     : integer range 0 to 2 ** 16 - 1;
  signal int_s2                     : integer range 0 to 2 ** 16 - 1;
  signal slv_current_adler_checksum : std_logic_vector(31 downto 0) := (others => '0');

begin

  proc_adler32 : process (isl_clk) is

    variable v_sum1 : integer range 0 to 2 ** 17 - 1;
    variable v_sum2 : integer range 0 to 2 ** 17 - 1;

  begin

    if (rising_edge(isl_clk)) then
      assert C_INPUT_BITWIDTH mod 8 = 0;
      assert not (isl_valid = '1' and state /= IDLE);

      case state is

        when IDLE =>
          if (isl_start = '1') then
            slv_current_adler_checksum <= x"00000001";
          end if;
          if (isl_valid = '1') then
            slv_data_in <= islv_data;
            state       <= CALC_S1;
          end if;

        when CALC_S1 =>
          v_sum1 := to_integer(unsigned(slv_current_adler_checksum(15 downto 0))) +
                    to_integer(unsigned(slv_data_in((0 + 1) * 8 - 1 downto 0 * 8)));
          -- Calculate the modulo manually, since it uses less resources and yields better timing.
          if (v_sum1 < 65521) then
            int_s1 <= v_sum1;
          else
            int_s1 <= v_sum1 - 65521;
          end if;
          state <= CALC_S2;

        when CALC_S2 =>
          v_sum2 := int_s1 + to_integer(unsigned(slv_current_adler_checksum(31 downto 16)));

          if (v_sum2 < 65521) then
            int_s2 <= v_sum2;
          elsif (v_sum2 < 65521 * 2) then
            int_s2 <= v_sum2 - 65521;
          else
            int_s2 <= v_sum2 - 65521 * 2;
          end if;
          state <= SEND_OUTPUT;

        when SEND_OUTPUT =>
          slv_current_adler_checksum <= std_logic_vector(to_unsigned(int_s2, 16)) &
                                        std_logic_vector(to_unsigned(int_s1, 16));
          state                      <= IDLE;

      end case;

    end if;

  end process proc_adler32;

  osl_ready <= '0' when isl_valid = '1' or state = CALC_S1 or state = CALC_S2 or state = SEND_OUTPUT else
               '1';
  oslv_data <= slv_current_adler_checksum;

end architecture behavioral;
