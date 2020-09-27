library ieee;
use ieee.std_logic_1164.all;

library png_lib;

library sim;
use sim.vunit_common_pkg.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_png_encoder is
  generic (
    runner_cfg           : string := "";

    C_IMG_WIDTH          : integer := 800;
    C_IMG_HEIGHT         : integer := 480;
    C_IMG_BIT_DEPTH      : integer range 1 to 16 := 8;
    C_COLOR_TYPE         : integer range 0 to 6 := 2;

    C_INPUT_BUFFER_SIZE  : integer range 3 to 258 := 12;
    C_SEARCH_BUFFER_SIZE : integer range 1 to 32768 := 12;

    C_BTYPE              : integer range 0 to 3 := 1;
    C_ROW_FILTER_TYPE    : integer range 0 to 5 := 0
  );
  port (
    isl_start  : in std_logic;
    isl_valid  : in std_logic;
    islv_data  : in std_logic_vector(7 downto 0);
    oslv_data  : out std_logic_vector(7 downto 0);
    osl_valid  : out std_logic;
    osl_rdy    : out std_logic;
    osl_finish : out std_logic
  );
end;

architecture tb of tb_png_encoder is
  signal sl_clk : std_logic := '0';
begin
  i_png_encoder : entity png_lib.png_encoder
  generic map (
    C_IMG_WIDTH => C_IMG_WIDTH,
    C_IMG_HEIGHT => C_IMG_HEIGHT,
    C_IMG_BIT_DEPTH => C_IMG_BIT_DEPTH,
    C_COLOR_TYPE => C_COLOR_TYPE,

    C_INPUT_BUFFER_SIZE => C_INPUT_BUFFER_SIZE,
    C_SEARCH_BUFFER_SIZE => C_SEARCH_BUFFER_SIZE,

    C_BTYPE => C_BTYPE,

    C_ROW_FILTER_TYPE => C_ROW_FILTER_TYPE
  )
  port map (
    isl_clk     => sl_clk,
    isl_start   => isl_start,
    isl_valid   => isl_valid,
    islv_data   => islv_data,
    oslv_data   => oslv_data,
    osl_valid   => osl_valid,
    osl_rdy     => osl_rdy,
    osl_finish  => osl_finish
  );
  
  clk_gen(sl_clk, 10 ns);
end;