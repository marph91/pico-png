-- https://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/MO/MemoryUsageGuideforiCE40Devices.ashx?document_id=47775
-- Default: 512 words, 8 bit each

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity bram is
  generic (
    C_ADDR_WIDTH : integer := 9;
    C_DATA_WIDTH : integer := 8
  );
  port (
    isl_clk : in    std_logic;
    -- writing
    isl_we     : in    std_logic;
    islv_waddr : in    std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    islv_data  : in    std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    -- reading
    islv_raddr : in    std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    oslv_data  : out   std_logic_vector(C_DATA_WIDTH - 1 downto 0)
  );
end entity bram;

architecture rtl of bram is

  type t_memory is array (0 to 2 ** C_ADDR_WIDTH - 1) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);

  signal a_mem : t_memory;

begin

  proc_bram : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_we = '1') then
        a_mem(to_integer(unsigned(islv_waddr))) <= islv_data;
      end if;
      oslv_data <= a_mem(to_integer(unsigned(islv_raddr)));
    end if;

  end process proc_bram;

end architecture rtl;
