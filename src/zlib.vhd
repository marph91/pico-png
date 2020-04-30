library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library png_lib;

library util;
use util.math_pkg.all;

entity zlib is
  generic (
    C_INPUT_BUFFER_SIZE  : integer range 3 to 258 := 10;
    C_SEARCH_BUFFER_SIZE : integer range 1 to 32768 := 12;

    C_BTYPE              : integer range 0 to 3 := 0 -- 0: no huffman encoding
  );
  port (
    isl_clk   : in std_logic;
    isl_flush : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(7 downto 0);
    oslv_data : out std_logic_vector(7 downto 0);
    osl_valid : out std_logic;
    osl_finish: out std_logic;
    osl_rdy   : out std_logic
  );
end;

architecture behavioral of zlib is
  -- CMF |  FLG
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
  constant C_DICTID : std_logic_vector(4*8-1 downto 0) := (others => '0');

  signal sl_valid_deflate : std_logic := '0';
  signal slv_data_deflate : std_logic_vector(7 downto 0) := (others => '0');
  signal int_valid_bits_deflate : integer range 1 to 72;
  signal sl_finish_deflate : std_logic := '0';
  signal sl_rdy_deflate : std_logic := '0';

  signal slv_data_adler32 : std_logic_vector(31 downto 0) := (others => '0');

  type t_states IS (IDLE, HEADERS, DEFLATE, FLUSH, ADLER32);
  signal state : t_states;

  -- bitbuffer
  signal int_output_index : integer range 0 to 72 := 0;
  signal buffered_output : std_logic_vector(71 downto 0) := (others => '0');
  signal slv_data_out : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';

begin
  i_deflate: entity png_lib.deflate
  generic map (
    C_INPUT_BUFFER_SIZE => C_INPUT_BUFFER_SIZE,
    C_SEARCH_BUFFER_SIZE => C_SEARCH_BUFFER_SIZE,
    C_BTYPE => C_BTYPE
  )
  port map (
    isl_clk         => isl_clk,
    isl_flush       => isl_flush,
    isl_valid       => isl_valid,
    islv_data       => islv_data,
    oslv_data       => slv_data_deflate,
    osl_valid       => sl_valid_deflate,
    osl_finish      => sl_finish_deflate,
    oint_valid_bits => int_valid_bits_deflate,
    osl_rdy         => sl_rdy_deflate
  );

  i_adler32: entity png_lib.adler32
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

  proc_fsm: process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      osl_finish <= '0';

      case state is
        when IDLE =>
          sl_valid_out <= '0';
          if isl_start = '1' then
            state <= HEADERS;
          end if;

        when HEADERS =>
          buffered_output(15 downto 0) <= C_CMF & C_FLG;
          int_output_index <= 16;
          state <= DEFLATE;

        when DEFLATE =>
          if sl_valid_deflate = '1' then
            -- sll needs more ressources
            -- buffered_output <= buffered_output sll int_valid_bits_deflate;
            buffered_output(buffered_output'HIGH downto int_valid_bits_deflate) <=
              buffered_output(buffered_output'HIGH - int_valid_bits_deflate downto 0);
            buffered_output(int_valid_bits_deflate-1 downto 0) <=
              slv_data_deflate(slv_data_deflate'HIGH downto slv_data_deflate'HIGH - int_valid_bits_deflate + 1);

            int_output_index <= int_output_index + int_valid_bits_deflate; -- not all bits of deflate output are used (the huffman output is variable)
          elsif int_output_index >= 8 then
            sl_valid_out <= '1';
            slv_data_out <= buffered_output(int_output_index - 1 downto int_output_index - 8);
            int_output_index <= int_output_index - 8;
          else
            sl_valid_out <= '0';
          end if;

          if sl_finish_deflate = '1' then
            state <= FLUSH;
          end if;

        when FLUSH =>
          if int_output_index >= 8 then
            sl_valid_out <= '1';
            slv_data_out <= buffered_output(int_output_index - 1 downto int_output_index - 8);
            int_output_index <= int_output_index - 8;
          elsif int_output_index > 0 then
            -- fill the byte up with zeros
            buffered_output(7 downto 0) <= buffered_output(7 downto 0) sll int_valid_bits_deflate;
            int_output_index <= 8;
            sl_valid_out <= '0';
          else
            sl_valid_out <= '0';
            int_output_index <= 4;
            state <= ADLER32;
          end if;

        when ADLER32 =>
          if int_output_index > 0 then
            sl_valid_out <= '1';
            slv_data_out <= slv_data_adler32(int_output_index * 8 - 1 downto (int_output_index-1) * 8);
            int_output_index <= int_output_index - 1;
          else
            sl_valid_out <= '0';
            state <= IDLE;
            osl_finish <= '1';
          end if;

      end case;
    end if;
  end process;

  osl_valid <= sl_valid_out;
  oslv_data <= slv_data_out;
  osl_rdy <= sl_rdy_deflate when (state = DEFLATE and int_output_index < 32) else '0';
end behavioral;