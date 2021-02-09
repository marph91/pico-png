library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.png_pkg.all;

entity crc32 is
  generic (
    C_INPUT_BITWIDTH : integer := 8
  );
  port (
    isl_clk   : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_INPUT_BITWIDTH - 1 downto 0);
    oslv_data : out   std_logic_vector(31 downto 0)
  );
end entity crc32;

architecture behavioral of crc32 is

  signal slv_current_crc : std_logic_vector(oslv_data'range) := (others => '0');

begin

  proc_crc32 : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_valid = '1') then
        slv_current_crc <= calculate_crc32(islv_data, slv_current_crc, '0');
      end if;
    end if;

  end process proc_crc32;

  oslv_data <= slv_current_crc(7 downto 0) & slv_current_crc(15 downto 8) &
               slv_current_crc(23 downto 16) & slv_current_crc(31 downto 24);

end architecture behavioral;
