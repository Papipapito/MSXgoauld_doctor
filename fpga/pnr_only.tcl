set_device GW2AR-LV18QN88C8/I7
add_file impl/gwsynthesis/project.vg
add_file tang9k.cst
add_file Z80_goauld_slim.sdc
set_option -use_sspi_as_gpio 1 -use_mspi_as_gpio 1 -top_module top -place_option 1 -route_option 1
run pnr
