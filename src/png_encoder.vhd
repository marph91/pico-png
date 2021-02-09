-- http://www.libpng.org/pub/png/spec/iso/index-object.html
-- https://www.ietf.org/rfc/rfc1950.txt
-- https://www.ietf.org/rfc/rfc1951.txt

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library png_lib;

library util;
  use util.math_pkg.all;
  use util.png_pkg.all;

entity png_encoder is
  generic (
    C_IMG_WIDTH  : integer := 800;
    C_IMG_HEIGHT : integer := 480;

    -- allowed bit depths, depending on color type: 1, 2, 4, 8, 16
    C_IMG_BIT_DEPTH : integer range 1 to 16 := 8;

    -- 0: greyscale
    -- 1: invalid
    -- 2: truecolor
    -- 3: indexed-color (not supported yet)
    -- 4: greyscale with alpha
    -- 5: invalid
    -- 6: truecolor with alpha
    C_COLOR_TYPE : integer range 0 to 6 := 2;

    -- LZSS parameters
    C_INPUT_BUFFER_SIZE     : integer range 3 to 258   := 12;
    C_SEARCH_BUFFER_SIZE    : integer range 1 to 32768 := 12;
    C_MAX_MATCH_LENGTH_USER : integer                  := 7;

    -- 0: no compression (not supported)
    -- 1: huffman encoding with a fixed table
    -- 2: huffman encoding with a dynamic table (not supported yet)
    -- 3: not allowed
    C_BTYPE : integer range 0 to 3 := 1;

    -- 0: no filter
    -- 1: sub filter (subtract the previous byte)
    -- 2-5: not supported yet
    C_ROW_FILTER_TYPE : integer range 0 to 5 := 0
  );
  port (
    isl_clk    : in    std_logic;
    isl_start  : in    std_logic;
    isl_valid  : in    std_logic;
    islv_data  : in    std_logic_vector(7 downto 0);
    oslv_data  : out   std_logic_vector(7 downto 0);
    osl_valid  : out   std_logic;
    osl_rdy    : out   std_logic;
    osl_finish : out   std_logic
  );
end entity png_encoder;

architecture behavioral of png_encoder is

  -- constants
  constant C_PNG_HEADER : std_logic_vector(8 * 8 - 1 downto 0) := x"89504e470d0a1a0a";

  constant C_IHDR_TYPE : std_logic_vector(4 * 8 - 1 downto 0) := x"49484452"; -- IHDR string encoded
  -- IHDR data composition:
  -- 32 bit: width
  -- 32 bit: height
  -- 8 bit: bit depth
  -- 8 bit: color type
  -- 2 bit: compression method (ONLY deflate/inflate compression with a 32K sliding window)
  -- 2 bit: filter method (ONLY adaptive filtering with five basic filter types)
  -- 2 bit: interlace method (0: no interlace, 1: Adam7 interlace)
  constant C_IHDR_DATA : std_logic_vector(13 * 8 - 1 downto 0) := std_logic_vector(to_unsigned(C_IMG_WIDTH, 32)) &
                                                                  std_logic_vector(to_unsigned(C_IMG_HEIGHT, 32)) &
                                                                  std_logic_vector(to_unsigned(C_IMG_BIT_DEPTH, 8)) &
                                                                  std_logic_vector(to_unsigned(C_COLOR_TYPE, 8)) &
                                                                  x"00" &
                                                                  x"00" &
                                                                  x"00";
  constant C_IHDR      : std_logic_vector((13 + 12) * 8 - 1 downto 0) := generate_chunk(C_IHDR_TYPE, C_IHDR_DATA);

  -- constant C_PLTE
  -- This chunk must appear for color type 3, and can appear for color types 2 and 6;
  -- it must not appear for color types 0 and 4.
  -- If this chunk does appear, it must precede the first IDAT chunk.

  constant C_IDAT_TYPE : std_logic_vector(4 * 8 - 1 downto 0) := x"49444154"; -- IDAT string encoded
  -- length of data, data itself and crc of IDAT have to be obtained at runtime

  signal slv_full_header : std_logic_vector(44 * 8 - 1 downto 0) := (others => '0');

  constant C_IEND_TYPE : std_logic_vector(4 * 8 - 1 downto 0) := x"49454e44"; -- IEND string encoded
  constant C_IEND      : std_logic_vector(12 * 8 - 1 downto 0) := generate_chunk(C_IEND_TYPE, "");

  constant C_IMG_DEPTH : integer range 1 to 4 := get_img_depth(C_COLOR_TYPE);

  -- row_filter
  signal sl_start_row_filter     : std_logic := '0';
  signal sl_valid_out_row_filter : std_logic := '0';
  signal slv_data_out_row_filter : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_rdy_row_filter       : std_logic := '0';

  -- zlib
  signal sl_valid_in_zlib  : std_logic := '0';
  signal slv_data_in_zlib  : std_logic_vector(7 downto 0) := (others => '0');
  signal slv_data_out_zlib : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_valid_out_zlib : std_logic := '0';
  signal sl_start_zlib     : std_logic := '0';
  signal sl_finish_zlib    : std_logic := '0';

  -- idat chunk
  signal sl_valid_in_crc32  : std_logic := '0';
  signal slv_data_in_crc32  : std_logic_vector(7 downto 0) := (others => '0');
  signal slv_data_out_crc32 : std_logic_vector(4 * 8 - 1 downto 0) := (others => '0');
  signal int_idat_length    : integer range 0 to 2 ** 31 - 1 := 0;

  -- interface
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_finish    : std_logic := '0';
  signal sl_flush     : std_logic := '0';

  -- internal

  type t_states is (IDLE, INIT_IDAT_CRC32, HEADERS, INIT_ROW_FILTER, ZLIB, IDAT_CRC, IEND);

  signal state : t_states;
  -- TODO: Do we need to assign these values with "isl_start"?
  signal int_channel_cnt : integer range 0 to C_IMG_DEPTH - 1 := C_IMG_DEPTH - 1;
  signal int_pixel_cnt   : integer range 0 to C_IMG_WIDTH * C_IMG_HEIGHT := C_IMG_WIDTH * C_IMG_HEIGHT;
  signal int_index       : integer range 0 to 44 := 0;

begin

  i_row_filter : entity png_lib.row_filter
    generic map (
      C_IMG_WIDTH       => C_IMG_WIDTH,
      C_IMG_HEIGHT      => C_IMG_HEIGHT,
      C_IMG_DEPTH       => C_IMG_DEPTH,
      C_ROW_FILTER_TYPE => C_ROW_FILTER_TYPE
    )
    port map (
      isl_clk   => isl_clk,
      isl_start => sl_start_row_filter,
      isl_get   => '1',
      isl_valid => isl_valid,
      islv_data => islv_data,
      oslv_data => slv_data_out_row_filter,
      osl_valid => sl_valid_out_row_filter,
      osl_rdy   => sl_rdy_row_filter
    );

  i_zlib : entity png_lib.zlib
    generic map (
      C_INPUT_BUFFER_SIZE     => C_INPUT_BUFFER_SIZE,
      C_SEARCH_BUFFER_SIZE    => C_SEARCH_BUFFER_SIZE,
      C_BTYPE                 => C_BTYPE,
      C_MAX_MATCH_LENGTH_USER => C_MAX_MATCH_LENGTH_USER
    )
    port map (
      isl_clk    => isl_clk,
      isl_flush  => sl_flush,
      isl_start  => sl_start_zlib,
      isl_valid  => sl_valid_in_zlib,
      islv_data  => slv_data_in_zlib,
      oslv_data  => slv_data_out_zlib,
      osl_valid  => sl_valid_out_zlib,
      osl_finish => sl_finish_zlib
    );

  i_crc32 : entity png_lib.crc32
    generic map (
      C_INPUT_BITWIDTH => slv_data_out_zlib'LENGTH
    )
    port map (
      isl_clk   => isl_clk,
      isl_valid => sl_valid_in_crc32,
      islv_data => slv_data_in_crc32,
      oslv_data => slv_data_out_crc32
    );

  proc_fsm : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      -- defaults
      sl_valid_out        <= '0';
      sl_finish           <= '0';
      sl_start_row_filter <= '0';
      sl_start_zlib       <= '0';
      sl_valid_in_crc32   <= '0';

      if (sl_valid_out_zlib = '1') then
        int_idat_length <= int_idat_length + 1;
      end if;

      case state is

        when IDLE =>
          if (isl_start = '1') then
            state     <= INIT_IDAT_CRC32;
            int_index <= 4;
          end if;

        when INIT_IDAT_CRC32 =>
          if (int_index /= 0) then
            sl_valid_in_crc32 <= '1';
            slv_data_in_crc32 <= get_byte(C_IDAT_TYPE, int_index);
            int_index         <= int_index - 1;
          else
            state         <= INIT_ROW_FILTER;
            sl_start_zlib <= '1';
          end if;

        when INIT_ROW_FILTER =>
          sl_start_row_filter <= '1';
          state               <= ZLIB;

        when ZLIB =>
          sl_valid_in_zlib  <= sl_valid_out_row_filter;
          slv_data_in_zlib  <= slv_data_out_row_filter;
          sl_valid_in_crc32 <= sl_valid_out_zlib;
          slv_data_in_crc32 <= slv_data_out_zlib;
          sl_valid_out      <= sl_valid_out_zlib;
          slv_data_out      <= slv_data_out_zlib;

          if (sl_finish_zlib = '1') then
            state     <= IDAT_CRC;
            int_index <= 4;
          end if;

        when IDAT_CRC =>
          if (int_index /= 0) then
            int_index    <= int_index - 1;
            slv_data_out <= get_byte(slv_data_out_crc32, int_index);
            sl_valid_out <= '1';
          else
            state     <= IEND;
            int_index <= 12;
          end if;

        when IEND =>
          if (int_index /= 0) then
            slv_data_out <= get_byte(C_IEND, int_index);
            sl_valid_out <= '1';
            int_index    <= int_index - 1;
          else
            state     <= HEADERS;
            int_index <= slv_full_header'LENGTH / 8;

            slv_full_header <= C_PNG_HEADER & C_IHDR & std_logic_vector(to_unsigned(int_idat_length, 32)) & C_IDAT_TYPE & x"000000";
          end if;

        when HEADERS =>
          -- send headers last, because length of idat is needed,
          -- which can be obtained only after all data got received
          if (int_index /= 0) then
            slv_data_out <= get_byte(slv_full_header, int_index);
            sl_valid_out <= '1';
            int_index    <= int_index - 1;
          else
            state     <= IDLE;
            sl_finish <= '1';
          end if;

      end case;

    end if;

  end process proc_fsm;

  proc_generate_flush_impulse : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      sl_flush <= '0';

      if (isl_valid = '1') then
        if (int_channel_cnt /= 0) then
          int_channel_cnt <= int_channel_cnt - 1;
        else
          int_channel_cnt <= C_IMG_DEPTH - 1;
          int_pixel_cnt   <= int_pixel_cnt - 1;
        end if;
      end if;

      -- isl_valid -> int_pixel_cnt -> sl_flush -> sl_finish_zlib
      if (int_pixel_cnt = 0) then
        int_pixel_cnt <= C_IMG_WIDTH * C_IMG_HEIGHT;
        sl_flush      <= '1';
      end if;
    end if;

  end process proc_generate_flush_impulse;

  osl_valid <= sl_valid_out;
  oslv_data <= slv_data_out;
  -- Adler and row filter can process only a word in two cycles.
  osl_rdy    <= not isl_valid and sl_rdy_row_filter when state = ZLIB else
                '0';
  osl_finish <= sl_finish;

end architecture behavioral;
