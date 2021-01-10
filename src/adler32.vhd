library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.png_pkg.all;

entity adler32 is
  generic (
    C_INPUT_BITWIDTH : integer range 1 to 32 := 10
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

  signal slv_current_adler_checksum : std_logic_vector(31 downto 0) := (others => '0');

begin

  proc_adler32 : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_start = '1') then
        slv_current_adler_checksum <= x"00000001";
      elsif (isl_valid = '1') then
        slv_current_adler_checksum <= calculate_adler32(islv_data, slv_current_adler_checksum);
      end if;
    end if;

  end process proc_adler32;

  oslv_data <= slv_current_adler_checksum;

end architecture behavioral;
