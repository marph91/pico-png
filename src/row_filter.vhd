library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.png_pkg.all;
  use util.math_pkg.all;

entity row_filter is
  generic (
    -- TODO: row filter type is allowed to change row wise -> signal
    C_ROW_FILTER_TYPE : integer range 0 to 4 := 1;
    C_IMG_WIDTH       : integer              := 10;
    C_IMG_HEIGHT      : integer              := 10;
    C_IMG_DEPTH       : integer              := 1
  );
  port (
    isl_clk   : in    std_logic;
    isl_start : in    std_logic;
    isl_get   : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(7 downto 0);
    oslv_data : out   std_logic_vector(7 downto 0);
    osl_valid : out   std_logic;
    osl_rdy   : out   std_logic
  );
end entity row_filter;

architecture behavioral of row_filter is

  signal int_column_cnt  : integer range 0 to C_IMG_WIDTH - 1  := 0;
  signal int_row_cnt     : integer range 0 to C_IMG_HEIGHT - 1 := 0;
  signal int_channel_cnt : integer range 0 to C_IMG_DEPTH - 1  := 0;

  -- Row filter is applied pixel-wise. I. e. for each channel separately.

  type t_last_pixel is array(0 to C_IMG_DEPTH - 1) of std_logic_vector(7 downto 0);

  signal a_last_pixel : t_last_pixel                 := (others => (others => '0'));
  signal sl_valid_out : std_logic                    := '0';
  signal slv_data_out : std_logic_vector(7 downto 0) := (others => '0');
  signal sl_rdy       : std_logic                    := '0';

  type t_states is (IDLE, SEND_FILTER_TYPE, APPLY_FILTER, DELAY);

  signal state : t_states;

begin

  proc_row_filter : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      -- defaults
      sl_valid_out <= '0';
      sl_rdy       <= '0';

      case state is

        when IDLE =>

          if (isl_start = '1') then
            state <= SEND_FILTER_TYPE;
          end if;

        when SEND_FILTER_TYPE =>

          if (isl_get = '1') then
            sl_valid_out <= '1';
            slv_data_out <= std_logic_vector(to_unsigned(C_ROW_FILTER_TYPE, 8));

            -- pixel left of the first scanline pixel are treated as 0
            a_last_pixel <= (others => (others => '0'));
            state        <= APPLY_FILTER;
          end if;

        when APPLY_FILTER =>

          sl_rdy <= '1';

          if (C_ROW_FILTER_TYPE = 0) then
            slv_data_out <= islv_data;
          elsif (C_ROW_FILTER_TYPE = 1) then
            -- unsigned arithmetic modulo 256 is used -> fits to 8 bit
            slv_data_out <= std_logic_vector(unsigned(islv_data) -
                                             unsigned(a_last_pixel(int_channel_cnt)));
            if (isl_valid = '1') then
              a_last_pixel(int_channel_cnt) <= islv_data;
            end if;
          else
            report "Row filter type " & to_string(C_ROW_FILTER_TYPE) & " not yet implemented."
              severity error;
          end if;

          if (isl_valid = '1') then
            sl_valid_out <= '1';
            if (int_channel_cnt /= C_IMG_DEPTH - 1) then
              int_channel_cnt <= int_channel_cnt + 1;
            else
              int_channel_cnt <= 0;
              if (int_column_cnt /= C_IMG_WIDTH - 1) then
                int_column_cnt <= int_column_cnt + 1;
              else
                int_column_cnt <= 0;
                if (int_row_cnt /= C_IMG_HEIGHT - 1) then
                  -- Adler can only handle one input in two cycles.
                  -- Slow it down here and at the DELAY state.
                  sl_rdy      <= '0';
                  state       <= DELAY;
                  int_row_cnt <= int_row_cnt + 1;
                else
                  state       <= IDLE;
                  int_row_cnt <= 0;
                end if;
              end if;
            end if;
          end if;

        when DELAY =>

          state <= SEND_FILTER_TYPE;

      end case;

    end if;

  end process proc_row_filter;

  oslv_data <= slv_data_out;
  osl_valid <= sl_valid_out;
  osl_rdy   <= sl_rdy;

end architecture behavioral;
