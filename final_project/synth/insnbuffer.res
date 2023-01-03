 
****************************************
Report : resources
Design : insnbuffer
Version: T-2022.03-SP3
Date   : Wed Nov  9 20:00:22 2022
****************************************

Resource Sharing Report for design insnbuffer in file
        /home/jpshen/eecs470/group6f22/r10k/verilog/insnbuffer.sv

===============================================================================
|          |              |            | Contained     |                      |
| Resource | Module       | Parameters | Resources     | Contained Operations |
===============================================================================
| r350     | DW01_cmp2    | width=3    |               | gt_119 gt_120 gt_121 |
| r351     | DW01_cmp2    | width=3    |               | gt_119_I2 gt_120_I2  |
|          |              |            |               | gt_121_I2            |
| r352     | DW01_cmp2    | width=3    |               | gt_119_I3 gt_120_I3  |
|          |              |            |               | gt_121_I3            |
| r353     | DW01_cmp2    | width=3    |               | gt_119_I4 gt_120_I4  |
|          |              |            |               | gt_121_I4            |
| r377     | DW01_cmp2    | width=3    |               | gt_48                |
| r379     | DW01_sub     | width=4    |               | sub_48               |
| r385     | DW01_add     | width=32   |               | add_65               |
| r387     | DW01_add     | width=32   |               | add_65_I2            |
| r389     | DW01_add     | width=32   |               | add_65_I3            |
| r395     | DW01_cmp2    | width=3    |               | lt_79                |
| r401     | DW01_add     | width=3    |               | add_93               |
| r403     | DW01_add     | width=3    |               | add_94               |
| r405     | DW01_inc     | width=3    |               | add_104              |
| r407     | DW01_add     | width=3    |               | add_105              |
| r409     | DW01_add     | width=3    |               | add_106              |
| r411     | DW01_inc     | width=3    |               | add_109              |
| r413     | DW01_add     | width=3    |               | add_110              |
| r415     | DW01_cmp2    | width=2    |               | gt_116               |
| r417     | DW01_cmp2    | width=2    |               | gt_116_I2            |
| r419     | DW01_cmp2    | width=2    |               | gt_116_I3            |
| r526     | DW01_add     | width=2    |               | add_2_root_add_79_3  |
| r528     | DW01_add     | width=3    |               | add_1_root_add_79_3  |
| r635     | DW01_add     | width=2    |               | add_2_root_add_79_6  |
| r637     | DW01_add     | width=3    |               | add_1_root_add_79_6  |
| r745     | DW01_add     | width=4    |               | add_1_root_sub_0_root_sub_48_2 |
| r747     | DW01_sub     | width=4    |               | sub_0_root_sub_0_root_sub_48_2 |
===============================================================================


Implementation Report
===============================================================================
|                    |                  | Current            | Set            |
| Cell               | Module           | Implementation     | Implementation |
===============================================================================
| add_65             | DW01_add         | rpl                |                |
| add_65_I2          | DW01_add         | rpl                |                |
| add_65_I3          | DW01_add         | rpl                |                |
===============================================================================

1
