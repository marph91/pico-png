# Toplevel interface

Generics:
| Generic | Supported values | Remarks |
| :--- | :--- | :--- |
| C_IMG_WIDTH | - | - |
| C_IMG_HEIGHT | - | - |
| C_IMG_DEPTH | 1, 2, 3, 4 | derived from color type |
| C_IMG_BIT_DEPTH | 8 bit | unit is **bit** |
| C_COLOR_TYPE | 0 (gray), 2 (RGB), 4 (gray + alpha), 6 (RGBA) | - |
| C_INPUT_BUFFER_SIZE | tested up to 12 | - |
| C_SEARCH_BUFFER_SIZE | tested up to 12 | - |
| C_BTYPE | 0 (no compression), 1 (fixed huffman) | - |
| C_ROW_FILTER_TYPE | 0 (no filter), 1 (subtraction filter) | - |

Signals:
| Signal | Remarks |
| :--- | :--- |
| isl_clk | Clock signal |
| isl_start | Signals the start for new image data. |
| isl_valid | Input data is valid. |
| islv_data | Input data: Raw image data with a bitwidth of eight bit. |
| oslv_data | Output data: Encoded PNG data with a bitwidth of eight bit. |
| osl_valid | Output data is valid. |
| osl_rdy | The encoder is ready for the next input. Input data should be only sent when this signal is active. |
| osl_finish | The encoder has finished processing the image. |

Note: The header gets transmitted at the end. The IDAT chunk needs a length, which is only available after compressing all data. Hence the length of the IDAT chunk can be transmitted only at the end. For an example how to reassemble the output data to a valid PNG image, see the method `assemble_and_check_png()` in `sim/png_encoder/run.py`.
