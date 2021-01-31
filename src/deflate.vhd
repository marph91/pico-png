library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library png_lib;

library util;
  use util.math_pkg.all;
  use util.png_pkg.all;

entity deflate is
  generic (
    C_INPUT_BUFFER_SIZE     : integer range 3 to 258   := 12;
    C_SEARCH_BUFFER_SIZE    : integer range 1 to 32768 := 12;
    C_BTYPE                 : integer range 0 to 3     := 1;
    C_MAX_MATCH_LENGTH_USER : integer                  := 8
  );
  port (
    isl_clk    : in    std_logic;
    isl_flush  : in    std_logic;
    isl_valid  : in    std_logic;
    islv_data  : in    std_logic_vector(7 downto 0);
    oslv_data  : out   std_logic_vector(7 downto 0);
    osl_valid  : out   std_logic;
    osl_finish : out   std_logic;
    osl_rdy    : out   std_logic
  );
end entity deflate;

architecture behavioral of deflate is

  signal sl_valid_in_lzss  : std_logic := '0';
  signal slv_data_in_lzss  : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_valid_out_lzss : std_logic := '0';
  signal slv_data_out_lzss : std_logic_vector(calc_huffman_bitwidth(C_BTYPE, C_INPUT_BUFFER_SIZE, C_SEARCH_BUFFER_SIZE, C_MAX_MATCH_LENGTH_USER) - 1 downto 0) := (others => '0');
  signal sl_finish_lzss    : std_logic := '0';
  signal sl_rdy_lzss       : std_logic := '0';

  signal sl_valid_in_huffman : std_logic := '0';
  signal slv_data_in_huffman : std_logic_vector(16 downto 0) := (others => '0');
  signal sl_rdy_huffman      : std_logic := '0';

  signal sl_valid_out : std_logic := '0';

begin

  gen_compression : if C_BTYPE = 0 generate
    sl_finish_lzss    <= isl_flush;
    sl_valid_out_lzss <= isl_valid;
    slv_data_out_lzss <= islv_data;
    sl_rdy_lzss       <= '1';
  else generate

    i_lzss : entity png_lib.lzss
      generic map (
        C_INPUT_BUFFER_SIZE     => C_INPUT_BUFFER_SIZE,
        C_SEARCH_BUFFER_SIZE    => C_SEARCH_BUFFER_SIZE,
        C_MAX_MATCH_LENGTH_USER => C_MAX_MATCH_LENGTH_USER
      )
      port map (
        isl_clk    => isl_clk,
        isl_flush  => isl_flush,
        isl_get    => sl_rdy_huffman,
        isl_valid  => isl_valid,
        islv_data  => islv_data,
        oslv_data  => slv_data_out_lzss,
        osl_valid  => sl_valid_out_lzss,
        osl_finish => sl_finish_lzss,
        osl_rdy    => sl_rdy_lzss
      );

  end generate gen_compression;

  i_huffman : entity png_lib.huffman
    generic map (
      C_BTYPE             => C_BTYPE,
      C_INPUT_BITWIDTH    => calc_huffman_bitwidth(C_BTYPE, C_INPUT_BUFFER_SIZE, C_SEARCH_BUFFER_SIZE, C_MAX_MATCH_LENGTH_USER),
      C_MATCH_LENGTH_BITS => log2(min_int(C_INPUT_BUFFER_SIZE, C_MAX_MATCH_LENGTH_USER) + 1)
    )
    port map (
      isl_clk    => isl_clk,
      isl_flush  => sl_finish_lzss,
      isl_valid  => sl_valid_out_lzss,
      islv_data  => slv_data_out_lzss,
      oslv_data  => oslv_data,
      osl_valid  => osl_valid,
      osl_finish => osl_finish,
      osl_rdy    => sl_rdy_huffman
    );

  osl_rdy <= sl_rdy_lzss and sl_rdy_huffman;

end architecture behavioral;
