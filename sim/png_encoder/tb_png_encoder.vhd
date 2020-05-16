-- only use the textio namespace to avoid naming conflicts with vunit, i. e. for "width"
use std.textio;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library png_lib;

library util;
use util.math_pkg.all;
use util.png_pkg.all;

library sim;
use sim.vunit_common_pkg.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_png_encoder is
  generic (
    runner_cfg           : string;
    id                   : string;

    C_IMG_WIDTH          : integer;
    C_IMG_HEIGHT         : integer;
    C_IMG_BIT_DEPTH      : integer;
    C_COLOR_TYPE         : integer;

    C_INPUT_BUFFER_SIZE  : integer;
    C_SEARCH_BUFFER_SIZE : integer;

    C_BTYPE              : integer;

    C_ROW_FILTER_TYPE    : integer
  );
end entity;

architecture tb of tb_png_encoder is
  signal sl_clk : std_logic := '0';
  signal sl_start : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_rdy : std_logic := '0';
  signal sl_finish : std_logic := '0';

  shared variable data_src : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;

begin
  dut : entity png_lib.png_encoder
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
    isl_start   => sl_start,
    isl_valid   => sl_valid_in,
    islv_data   => slv_data_in,
    oslv_data   => slv_data_out,
    osl_valid   => sl_valid_out,
    osl_rdy     => sl_rdy,
    osl_finish  => sl_finish
  );
  
  clk_gen(sl_clk, 10 ns);

  main: process
  begin
    test_runner_setup(runner, runner_cfg);
    -- https://github.com/VUnit/vunit/blob/209e27d28cf9abb93b2d4f7ccc9e26882df11859/vunit/vhdl/array/src/array_pkg.vhd#L38
    data_src := load_raw(tb_path(runner_cfg) & "gen/input_" & id & ".raw", 8, false);

    check_equal(width(data_src), C_IMG_WIDTH*C_IMG_HEIGHT*get_img_depth(C_COLOR_TYPE)*C_IMG_BIT_DEPTH/8);
    check_equal(height(data_src), 1);
    check_equal(depth(data_src), 1);

    wait until (stimuli_done and
                data_check_done and
                rising_edge(sl_clk));
    test_runner_cleanup(runner);
    wait;
  end process;

  proc_stimuli: process
  begin
    wait until rising_edge(sl_clk);
    sl_start <= '1';
    wait until rising_edge(sl_clk);
    sl_start <= '0';

    for i in 0 to width(data_src)-1 loop
      wait until rising_edge(sl_clk) and sl_rdy = '1';
      sl_valid_in <= '1';
      slv_data_in <= std_logic_vector(to_unsigned(get(data_src, i, 0), slv_data_in'length));
      wait until rising_edge(sl_clk);
      sl_valid_in <= '0';
      wait until rising_edge(sl_clk);
      wait until rising_edge(sl_clk);
    end loop;

    stimuli_done <= true;
    wait;
  end process;

  proc_data_check: process
    file file_handler     : textio.text open write_mode is tb_path(runner_cfg) & "gen/png_" & id & ".txt";
    variable row          : textio.line;
    variable v_data_write : integer;
  begin
    wait until rising_edge(sl_clk);
    data_check_done <= false;

    while sl_finish = '0' loop
      if sl_valid_out = '1' then
        textio.write(row, to_string(slv_data_out));
        textio.writeline(file_handler, row);
      end if;
      wait until rising_edge(sl_clk);
    end loop;
    
    report ("Done checking");
    data_check_done <= true;
    wait;
  end process;
end;