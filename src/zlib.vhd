library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library png_lib;

library util;
  use util.math_pkg.all;
  use util.png_pkg.all;

entity zlib is
  generic (
    C_INPUT_BUFFER_SIZE     : integer range 3 to 258   := 10;
    C_SEARCH_BUFFER_SIZE    : integer range 1 to 32768 := 12;
    C_BTYPE                 : integer range 0 to 3     := 1;
    C_MAX_MATCH_LENGTH_USER : integer                  := 8
  );
  port (
    isl_clk    : in    std_logic;
    isl_flush  : in    std_logic;
    isl_start  : in    std_logic;
    isl_valid  : in    std_logic;
    islv_data  : in    std_logic_vector(7 downto 0);
    oslv_data  : out   std_logic_vector(7 downto 0);
    osl_valid  : out   std_logic;
    osl_finish : out   std_logic
  );
end entity zlib;

architecture behavioral of zlib is

  -- CMF  |  FLG
  -- 0x08 | .... - window buffer size = 0
  -- 0x78 | 0x01 - No Compression/low
  -- 0x78 | 0x9C - Default Compression
  -- 0x78 | 0xDA - Best Compression

  -- CMF:
  -- bits 0 to 3  CM     Compression method
  -- bits 4 to 7  CINFO  Compression info
  constant C_CMF : std_logic_vector(7 downto 0) := x"78";
  -- FLG:
  -- bits 0 to 4  FCHECK  (check bits for CMF and FLG) -> multiple of 31??
  -- bit  5       FDICT   (preset dictionary)
  -- bits 6 to 7  FLEVEL  (compression level)
  constant C_FLG : std_logic_vector(7 downto 0) := x"01";

  -- only used if FDICT = '1'
  constant C_DICTID : std_logic_vector(4 * 8 - 1 downto 0) := (others => '0');

  signal sl_valid_deflate       : std_logic := '0';
  signal slv_data_deflate       : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_finish_deflate      : std_logic := '0';
  signal sl_finish_deflate_save : std_logic := '0';
  signal sl_finish              : std_logic := '0';

  signal slv_data_adler32 : std_logic_vector(31 downto 0) := (others => '0');

  type t_states is (IDLE, HEADER_CMF, HEADER_FLG, DEFLATE, ADLER32);

  signal state : t_states;

  signal int_output_byte_index : integer range 0 to 4 := 0;
  signal slv_data_out          : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_valid_out          : std_logic := '0';

begin

  i_deflate : entity png_lib.deflate
    generic map (
      C_INPUT_BUFFER_SIZE     => C_INPUT_BUFFER_SIZE,
      C_SEARCH_BUFFER_SIZE    => C_SEARCH_BUFFER_SIZE,
      C_BTYPE                 => C_BTYPE,
      C_MAX_MATCH_LENGTH_USER => C_MAX_MATCH_LENGTH_USER
    )
    port map (
      isl_clk    => isl_clk,
      isl_flush  => isl_flush,
      isl_valid  => isl_valid,
      islv_data  => islv_data,
      oslv_data  => slv_data_deflate,
      osl_valid  => sl_valid_deflate,
      osl_finish => sl_finish_deflate
    );

  i_adler32 : entity png_lib.adler32
    generic map (
      C_INPUT_BITWIDTH => islv_data'LENGTH
    )
    port map (
      isl_clk   => isl_clk,
      isl_start => isl_start,
      isl_valid => isl_valid,
      islv_data => islv_data,
      oslv_data => slv_data_adler32
    );

  proc_fsm : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      -- defaults
      sl_finish    <= '0';
      sl_valid_out <= '0';

      -- Save the finish impulse of deflate in case it can't be processed directly.
      if (sl_finish_deflate = '1') then
        sl_finish_deflate_save <= '1';
      end if;

      case state is

        when IDLE =>
          if (isl_start = '1') then
            state <= HEADER_CMF;
          end if;

        when HEADER_CMF =>
          sl_valid_out <= '1';
          slv_data_out <= C_CMF;
          state        <= HEADER_FLG;

        when HEADER_FLG =>
          sl_valid_out <= '1';
          slv_data_out <= C_FLG;
          state        <= DEFLATE;

        when DEFLATE =>
          if (sl_valid_deflate = '1') then
            slv_data_out <= slv_data_deflate;
            sl_valid_out <= '1';
          elsif (sl_finish_deflate_save = '1') then
            sl_finish_deflate_save <= '0';
            int_output_byte_index  <= 4;
            state                  <= ADLER32;
          end if;

        when ADLER32 =>
          if (int_output_byte_index /= 0) then
            sl_valid_out          <= '1';
            slv_data_out          <= get_byte(slv_data_adler32, int_output_byte_index);
            int_output_byte_index <= int_output_byte_index - 1;
          else
            state     <= IDLE;
            sl_finish <= '1';
          end if;

      end case;

    end if;

  end process proc_fsm;

  osl_valid  <= sl_valid_out;
  oslv_data  <= slv_data_out;
  osl_finish <= sl_finish;

end architecture behavioral;
