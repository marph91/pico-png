library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package huffman_pkg is

  type t_code is record
    bits  : integer;
    value : integer;
  end record t_code;

  type t_huffman_code is record
    sl_match       : std_logic;
    lit            : t_code;
    length         : t_code;
    length_extra   : t_code;
    distance       : t_code;
    distance_extra : t_code;
  end record t_huffman_code;

  procedure assert_huffman_code_valid (
    huffman_code : t_huffman_code
  );

  function get_literal_code (
    raw_value : integer
  ) return t_code;

  function get_length_code (
    raw_value : integer
  ) return t_code;

  function get_length_extra_code (
    raw_value : integer
  ) return t_code;

  function get_distance_code (
    raw_value : integer
  ) return t_code;

  function get_distance_extra_code (
    raw_value : integer
  ) return t_code;

end package huffman_pkg;

package body huffman_pkg is

  -- Assert a integer value is in a specific range.

  procedure assert_in_range (
    name    : string;
    minimum : integer;
    maximum : integer;
    value   : integer
  ) is
  begin

    assert (minimum <= value and value <= maximum)
      report "invalid " & name & " " & to_string(value);

  end procedure;

  -- Assert a huffman code is valid.
  -- For details, see RFC1951 3.2.5. Compressed blocks (length and distance codes)

  procedure assert_huffman_code_valid (
    huffman_code : t_huffman_code
  ) is
  begin

    if (huffman_code.sl_match = '0') then
      assert_in_range("literal bitwidth", 8, 9, huffman_code.lit.bits);
      assert_in_range("literal value", 48, 511, huffman_code.lit.value);
    else
      assert_in_range("length bitwidth", 7, 8, huffman_code.length.bits);
      assert_in_range("length value", 257, 285, huffman_code.length.value);

      assert_in_range("length extra bitwidth", 0, 5, huffman_code.length_extra.bits);
      assert_in_range("length extra value", 0, 2 ** 5 - 1, huffman_code.length_extra.value);

      assert_in_range("distance bitwidth", 5, 5, huffman_code.distance.bits);
      assert_in_range("distance value", 0, 29, huffman_code.distance.value);

      assert_in_range("distance extra bitwidth", 0, 13, huffman_code.distance.bits);
      assert_in_range("distance extra value", 0, 2 ** 13 - 1, huffman_code.distance.value);
    end if;

  end procedure;

  function get_literal_code (
    raw_value : integer
  ) return t_code is

    variable v_code : t_code;

  begin

    if (raw_value <= 143) then
      v_code := (8, 48 + raw_value);
    else
      v_code := (9, 256 + raw_value);
    end if;

    return v_code;

  end function;

  function get_length_code (
    raw_value : integer
  ) return t_code is

    variable v_code : t_code;

  begin

    if (raw_value <= 10) then
      v_code.value := 254 + raw_value;
    elsif (raw_value <= 12) then
      v_code.value := 265;
    elsif (raw_value <= 14) then
      v_code.value := 266;
    elsif (raw_value <= 16) then
      v_code.value := 267;
    elsif (raw_value <= 18) then
      v_code.value := 268;
    elsif (raw_value <= 22) then
      v_code.value := 269;
    elsif (raw_value <= 26) then
      v_code.value := 270;
    elsif (raw_value <= 30) then
      v_code.value := 271;
    elsif (raw_value <= 34) then
      v_code.value := 272;
    elsif (raw_value <= 42) then
      v_code.value := 273;
    elsif (raw_value <= 50) then
      v_code.value := 274;
    elsif (raw_value <= 58) then
      v_code.value := 275;
    elsif (raw_value <= 66) then
      v_code.value := 276;
    elsif (raw_value <= 82) then
      v_code.value := 277;
    elsif (raw_value <= 98) then
      v_code.value := 278;
    elsif (raw_value <= 114) then
      v_code.value := 279;
    elsif (raw_value <= 130) then
      v_code.value := 280;
    elsif (raw_value <= 162) then
      v_code.value := 281;
    elsif (raw_value <= 194) then
      v_code.value := 282;
    elsif (raw_value <= 226) then
      v_code.value := 283;
    elsif (raw_value <= 257) then
      v_code.value := 284;
    elsif (raw_value = 258) then
      v_code.value := 285;
    else
      report "invalid length " & to_string(raw_value)
        severity error;
    end if;

    if (raw_value <= 114) then
      v_code.bits := 7;
    else
      v_code.bits := 8;
    end if;

    return v_code;

  end function;

  function get_length_extra_code (
    raw_value : integer
  ) return t_code is

    variable v_code            : t_code;
    variable v_int_start_value : integer;

  begin

    if (raw_value <= 10 or raw_value = 285) then
      v_code := (0, 0);
      return v_code;
    end if;

    if (raw_value <= 18) then
      v_code.bits       := 1;
      v_int_start_value := 11;
    elsif (raw_value <= 34) then
      v_code.bits       := 2;
      v_int_start_value := 19;
    elsif (raw_value <= 66) then
      v_code.bits       := 3;
      v_int_start_value := 35;
    elsif (raw_value <= 130) then
      v_code.bits       := 4;
      v_int_start_value := 67;
    elsif (raw_value <= 257) then
      v_code.bits       := 5;
      v_int_start_value := 131;
    else
      report "invalid length " & to_string(raw_value)
        severity error;
    end if;

    v_code.value := raw_value - v_int_start_value;
    return v_code;

  end function;

  function get_distance_code (
    raw_value : integer
  ) return t_code is

    variable v_code : t_code;

  begin

    if (raw_value <= 4) then
      v_code.value := raw_value - 1;
    elsif (raw_value <= 6) then
      v_code.value := 4;
    elsif (raw_value <= 8) then
      v_code.value := 5;
    elsif (raw_value <= 12) then
      v_code.value := 6;
    elsif (raw_value <= 16) then
      v_code.value := 7;
    elsif (raw_value <= 24) then
      v_code.value := 8;
    elsif (raw_value <= 32) then
      v_code.value := 9;
    elsif (raw_value <= 48) then
      v_code.value := 10;
    elsif (raw_value <= 64) then
      v_code.value := 11;
    elsif (raw_value <= 96) then
      v_code.value := 12;
    elsif (raw_value <= 128) then
      v_code.value := 13;
    elsif (raw_value <= 192) then
      v_code.value := 14;
    elsif (raw_value <= 256) then
      v_code.value := 15;
    elsif (raw_value <= 384) then
      v_code.value := 16;
    elsif (raw_value <= 512) then
      v_code.value := 17;
    elsif (raw_value <= 768) then
      v_code.value := 18;
    elsif (raw_value <= 1024) then
      v_code.value := 19;
    elsif (raw_value <= 1536) then
      v_code.value := 20;
    elsif (raw_value <= 2048) then
      v_code.value := 21;
    elsif (raw_value <= 3072) then
      v_code.value := 22;
    elsif (raw_value <= 4096) then
      v_code.value := 23;
    elsif (raw_value <= 6144) then
      v_code.value := 24;
    elsif (raw_value <= 8192) then
      v_code.value := 25;
    elsif (raw_value <= 12288) then
      v_code.value := 26;
    elsif (raw_value <= 16384) then
      v_code.value := 27;
    elsif (raw_value <= 24576) then
      v_code.value := 28;
    elsif (raw_value <= 32768) then
      v_code.value := 29;
    else
      report "invalid distance " & to_string(raw_value)
        severity error;
    end if;

    v_code.bits := 5;
    return v_code;

  end function;

  function get_distance_extra_code (
    raw_value : integer
  ) return t_code is

    variable v_code            : t_code;
    variable v_int_start_value : integer;

  begin

    if (raw_value <= 4) then
      v_code := (0, 0);
      return v_code;
    end if;

    -- TODO: Isn't more separation needed?
    if (raw_value <= 8) then
      v_code.bits       := 1;
      v_int_start_value := 5;
    elsif (raw_value <= 16) then
      v_code.bits       := 2;
      v_int_start_value := 9;
    elsif (raw_value <= 32) then
      v_code.bits       := 3;
      v_int_start_value := 17;
    elsif (raw_value <= 64) then
      v_code.bits       := 4;
      v_int_start_value := 33;
    elsif (raw_value <= 128) then
      v_code.bits       := 5;
      v_int_start_value := 65;
    elsif (raw_value <= 256) then
      v_code.bits       := 6;
      v_int_start_value := 129;
    elsif (raw_value <= 512) then
      v_code.bits       := 7;
      v_int_start_value := 257;
    elsif (raw_value <= 1024) then
      v_code.bits       := 8;
      v_int_start_value := 513;
    elsif (raw_value <= 2048) then
      v_code.bits       := 9;
      v_int_start_value := 1025;
    elsif (raw_value <= 4096) then
      v_code.bits       := 10;
      v_int_start_value := 2049;
    elsif (raw_value <= 8192) then
      v_code.bits       := 11;
      v_int_start_value := 4097;
    elsif (raw_value <= 16384) then
      v_code.bits       := 12;
      v_int_start_value := 8193;
    elsif (raw_value <= 32768) then
      v_code.bits       := 13;
      v_int_start_value := 16384;
    else
      report "invalid distance " & to_string(raw_value)
        severity error;
    end if;

    v_code.value := raw_value - v_int_start_value;
    return v_code;

  end function;

end package body huffman_pkg;
