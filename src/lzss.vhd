library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library png_lib;

library util;
  use util.math_pkg.all;
  use util.png_pkg.all;

entity lzss is
  generic (
    C_INPUT_BUFFER_SIZE     : integer range 3 to 258   := 10;
    C_SEARCH_BUFFER_SIZE    : integer range 1 to 32768 := 12;
    C_MIN_MATCH_LENGTH      : integer range 3 to 16    := 3;
    C_MAX_MATCH_LENGTH_USER : integer                  := 8
  );
  port (
    isl_clk    : in    std_logic;
    isl_flush  : in    std_logic;
    isl_valid  : in    std_logic;
    islv_data  : in    std_logic_vector(7 downto 0);
    oslv_data  : out   std_logic_vector(calc_huffman_bitwidth(1, C_INPUT_BUFFER_SIZE, C_SEARCH_BUFFER_SIZE, C_MAX_MATCH_LENGTH_USER) - 1 downto 0);
    osl_valid  : out   std_logic;
    osl_finish : out   std_logic
  );
end entity lzss;

architecture behavioral of lzss is

  constant C_MAX_MATCH_LENGTH : integer := min_int(C_INPUT_BUFFER_SIZE, C_MAX_MATCH_LENGTH_USER);

  -- 0 is part of the input buffer:
  -- search buffer: C_SEARCH_BUFFER_SIZE + 1 downto 1
  -- input buffer: 0 downto -(C_INPUT_BUFFER_SIZE - 1)

  type t_slv_buffer is array(C_SEARCH_BUFFER_SIZE downto -(C_INPUT_BUFFER_SIZE - 1)) of std_logic_vector(7 downto 0);

  signal a_buffer : t_slv_buffer := (others => (others => 'U'));

  type t_match is record
    -- Maximum is 15 bit distance/offset and 8 bit length.
    int_offset     : integer range 0 to C_SEARCH_BUFFER_SIZE;
    int_length     : integer range 0 to C_MAX_MATCH_LENGTH;
    slv_next_datum : std_logic_vector(7 downto 0);
  end record t_match;

  signal rec_best_match : t_match := (0, 0, (others => '0'));

  type t_states is (IDLE, FILL, FAST_FILL, FIND_MATCH_OFFSET, FIND_MATCH_LENGTH);

  signal state : t_states := IDLE;

  signal int_datums_to_fill : integer range 0 to C_INPUT_BUFFER_SIZE := 0;
  signal sl_valid_out       : std_logic                              := '0';

  signal int_datums_to_flush : integer range 0 to C_INPUT_BUFFER_SIZE := 0;
  signal sl_last_input       : std_logic                              := '0';
  signal sl_flush            : std_logic                              := '0';
  signal sl_finish           : std_logic                              := '0';

  signal int_match_offset : integer range 0 to C_SEARCH_BUFFER_SIZE;

  -- Helper signals to visualize the output better.
  signal slv_literal_data : std_logic_vector(oslv_data'high - 1 downto oslv_data'low);
  signal slv_match_offset : std_logic_vector(max_int(log2(C_SEARCH_BUFFER_SIZE), 8 - log2(C_MAX_MATCH_LENGTH + 1)) - 1 downto 0);
  signal slv_match_length : std_logic_vector(log2(C_MAX_MATCH_LENGTH + 1) - 1 downto 0);

  -- Input buffer BRAM.
  constant C_ADDR_WIDTH      : integer                                     := 9;
  signal   slv_bram_raddr    : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal   slv_bram_raddr_d1 : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal   slv_bram_waddr    : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal   slv_bram_waddr_d1 : std_logic_vector(C_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal   slv_bram_data_out : std_logic_vector(islv_data'range);

begin

  i_input_buffer : entity png_lib.bram
    generic map (
      C_ADDR_WIDTH => C_ADDR_WIDTH,
      C_DATA_WIDTH => 8
    )
    port map (
      isl_clk => isl_clk,

      isl_we     => isl_valid,
      islv_waddr => slv_bram_waddr,
      islv_data  => islv_data,

      islv_raddr => slv_bram_raddr,
      oslv_data  => slv_bram_data_out
    );

  proc_lzss : process (isl_clk) is

    variable v_int_match_length : integer range C_MIN_MATCH_LENGTH to C_MAX_MATCH_LENGTH;
    -- Search index = 0 means no match found.
    variable v_int_match_offset : integer range 0 to C_SEARCH_BUFFER_SIZE;

  begin

    if (rising_edge(isl_clk)) then
      -- defaults
      sl_finish    <= '0';
      sl_valid_out <= '0';

      if (isl_valid = '1') then
        slv_bram_waddr <= std_logic_vector(unsigned(slv_bram_waddr) + 1);
      end if;

      -- One cycle write and read delay.
      slv_bram_waddr_d1 <= slv_bram_waddr;
      slv_bram_raddr_d1 <= slv_bram_raddr;

      if (isl_flush = '1') then
        sl_flush <= '1';
      end if;

      case state is

        when IDLE =>

          int_datums_to_fill <= C_INPUT_BUFFER_SIZE;
          state              <= FILL;

        when FILL =>

          -- TODO: Simplify this state.

          -- Fill the buffer at three occasions:
          -- 1. Initially.
          -- 2. After a match or literal.
          -- 3. For flushing at the end.
          if (slv_bram_waddr_d1 /= slv_bram_raddr) then
            -- First cycle: Assign new BRAM address.
            -- Second cycle: Assign BRAM output.
            if (slv_bram_raddr = slv_bram_raddr_d1) then
              slv_bram_raddr <= std_logic_vector(unsigned(slv_bram_raddr) + 1);

              int_datums_to_fill <= int_datums_to_fill - 1;
              a_buffer           <= a_buffer(a_buffer'left - 1 downto a_buffer'right) & slv_bram_data_out;

              if (int_datums_to_fill - 1 = 0) then
                state          <= FIND_MATCH_OFFSET;
                rec_best_match <= (0, 0, a_buffer(-1));
              end if;
            end if;
          elsif (sl_flush = '1') then
            sl_flush            <= '0';
            int_datums_to_flush <= C_INPUT_BUFFER_SIZE - 1;
          elsif (int_datums_to_flush /= 0) then
            int_datums_to_fill  <= int_datums_to_fill - 1;
            a_buffer            <= a_buffer(a_buffer'left - 1 downto a_buffer'right) & "UUUUUUUU";
            int_datums_to_flush <= int_datums_to_flush - 1;
            if (int_datums_to_flush = 1) then
              sl_last_input <= '1';
            end if;

            if (int_datums_to_fill - 1 = 0) then
              state          <= FIND_MATCH_OFFSET;
              rec_best_match <= (0, 0, a_buffer(-1));
            end if;
          elsif (sl_last_input = '1') then
            sl_last_input <= '0';
            state         <= IDLE;
            sl_finish     <= '1';
          end if;

        when FAST_FILL =>

          int_datums_to_fill <= int_datums_to_fill - 1;
          a_buffer           <= a_buffer(a_buffer'left - 1 downto a_buffer'right) & slv_bram_data_out;

          if (int_datums_to_fill - 1 = 0) then
            state          <= FIND_MATCH_OFFSET;
            rec_best_match <= (0, 0, a_buffer(-1));
          else
            slv_bram_raddr <= std_logic_vector(unsigned(slv_bram_raddr) + 1);
          end if;

        when FIND_MATCH_OFFSET =>

          -- Try to find the first C_MIN_MATCH_LENGTH elements of the input buffer
          -- in the search buffer.
          v_int_match_offset := 0;

          for current_index in 1 to C_SEARCH_BUFFER_SIZE loop

            -- TODO: We look in the input buffer for searching.
            if (a_buffer(current_index downto current_index - C_MIN_MATCH_LENGTH + 1) =
                a_buffer(0 downto - C_MIN_MATCH_LENGTH + 1)) then
              v_int_match_offset := current_index;
            end if;

          end loop;

          if (v_int_match_offset = 0) then
            -- literal
            int_datums_to_fill <= 1;

            -- output
            sl_valid_out <= '1';
            if (sl_last_input = '0') then
              state <= FILL;
            else
              sl_last_input <= '0';
              state         <= IDLE;
              sl_finish     <= '1';
            end if;
          else
            -- match
            state            <= FIND_MATCH_LENGTH;
            int_match_offset <= v_int_match_offset;
          end if;

        when FIND_MATCH_LENGTH =>

          -- Get the length of the match if a matching element was found.
          -- I. e. try to match the next elements of search and input buffer.

          -- Note: v_int_match_length is one-based, match_length and input buffer are zero-based.
          v_int_match_length := C_MAX_MATCH_LENGTH;

          for match_length in C_MIN_MATCH_LENGTH to C_MAX_MATCH_LENGTH - 1 loop

            if (a_buffer(int_match_offset - match_length) /= a_buffer(-match_length)) then
              -- Don't look for further matches, since we got a mismatch.
              -- Assign the match length of the last loop, since it was the last match.
              v_int_match_length := match_length;
              exit;
            end if;

          end loop;

          rec_best_match <= (int_match_offset, v_int_match_length, a_buffer(-v_int_match_length + 1));

          int_datums_to_fill <= v_int_match_length;

          -- output
          sl_valid_out <= '1';
          if (sl_last_input = '0') then
            -- Use fast fill to avoid BRAM overflow.
            -- Add C_MAX_MATCH_LENGTH instead of v_int_match_length to relax timing.
            if (sl_flush = '0' and unsigned(slv_bram_raddr) + C_MAX_MATCH_LENGTH < unsigned(slv_bram_waddr)) then
              state          <= FAST_FILL;
              slv_bram_raddr <= std_logic_vector(unsigned(slv_bram_raddr) + 1);
            else
              state <= FILL;
            end if;
          else
            sl_last_input <= '0';
            state         <= IDLE;
            sl_finish     <= '1';
          end if;

      end case;

    end if;

  end process proc_lzss;

  -- In case of a literal (no match found), fill the output data with zeros.
  slv_literal_data <= a_buffer(0) & (slv_literal_data'high - a_buffer(0)'length downto 0 => '0');
  -- In case of a match, assure that the output bitwidth is at least 8.
  -- 8 bits are needed to represent a literal.
  slv_match_offset <= std_logic_vector(to_unsigned(rec_best_match.int_offset, max_int(log2(C_SEARCH_BUFFER_SIZE), 8 - log2(C_MAX_MATCH_LENGTH + 1))));
  slv_match_length <= std_logic_vector(to_unsigned(rec_best_match.int_length, log2(C_MAX_MATCH_LENGTH + 1)));

  oslv_data  <= '0' & slv_literal_data when int_datums_to_fill = 1 else
                '1' & slv_match_offset & slv_match_length;
  osl_valid  <= sl_valid_out;
  osl_finish <= sl_finish;

end architecture behavioral;
