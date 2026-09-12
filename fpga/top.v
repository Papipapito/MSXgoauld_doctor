`define ENABLE_V9958
`define ENABLE_BIOS
`define ENABLE_MAPPER //bios required
`define ENABLE_WAIT //extra wait state for mreq+wr
//`define ENABLE_WAIT_ADAPTIVE //wait required
//`define SWAP23
// DIAG_SLIM (Goa'uld Doctor build, see msx_debug/diag_macros.v) keeps only
// what the diagnostic needs: T80, V9958+HDMI, SDRAM, flash loader, BIOS/
// subrom/mapper decode, internal PPI/RTC, wait FSM, bus_monitor, Doctor ROM.
// Out: OPLL/SCC/megaram, SD card/Nextor, settings ports + flash writer,
// WiFi UART, USB keyboard/joystick link, kanji, version guard, debug UART.
`ifndef DIAG_SLIM
`define ENABLE_SOUND //v9958, bios required
`define ENABLE_SCAN_LINES
`define ENABLE_SDCARD
`define ENABLE_CONFIG
`define ENABLE_WIFI
`endif

module top
#(
    parameter SD_SLOT = 3
)(
    input wire ex_clk_27m,
    input wire s1,
    input wire s2,

    input wire ex_bus_wait_n,
    input wire ex_bus_int_n,
    input wire ex_bus_reset_n,
    input wire ex_bus_clk_3m6,

    inout wire [7:0] ex_bus_data,
    
    output wire [1:0] ex_msel,
    output wire ex_bus_m1_n,
    output wire ex_bus_rfsh_n,
    output wire ex_bus_mreq_n,
    output wire ex_bus_iorq_n,
    output wire ex_bus_rd_n,
    output wire ex_bus_wr_n,

    output wire ex_bus_data_reverse_n,
    //output wire ex_bus_data_reverse,
    output wire [7:0] ex_bus_mp,

    //hdmi out
    output wire [2:0] data_p,
    output wire [2:0] data_n,
    output wire clk_p,
    output wire clk_n,

    // flash
    output wire mspi_cs,
    output wire mspi_sclk,
    inout wire mspi_miso,
    inout wire mspi_mosi,

    // MicroSD
    output wire sd_sclk,
    inout wire sd_cmd,      // MOSI
    inout  wire sd_dat0,     // MISO
    output wire sd_dat1,     // 1
    output wire sd_dat2,     // 1
    output wire sd_dat3,     // 1

    //uart (ESP link; the pins are in the cst, so always declared)
    output wire uart_tx,
    input wire uart_rx,

    //usb uart
    output wire usb_uart_tx,

    // USB-keyboard virtual matrix UART RX (from RP2040 Pico GPIO0 TX -> pin 75)
    input wire kbd_uart_rx_pin,

    // Magic ports for SDRAM to be inferred
    output wire O_sdram_clk,
    output wire O_sdram_cke,
    output wire O_sdram_cs_n, // chip select
    output wire O_sdram_cas_n, // columns address select
    output wire O_sdram_ras_n, // row address select
    output wire O_sdram_wen_n, // write enable
    inout wire [31:0] IO_sdram_dq, // 32 bit bidirectional data bus
    output wire [10:0] O_sdram_addr, // 11 bit multiplexed address bus
    output wire [1:0] O_sdram_ba, // two banks
    output wire [3:0] O_sdram_dqm // 32/4

    //output wire SLTSL3

);

initial begin

end
    //`default_nettype none

    //assign SLTSL3 = bus_mreq_disable ^ bus_iorq_disable ^ xffh ^ xffl ^ mapper_read ^ exp_slotx_req_r ^ bios_req ^ subrom_req ^ vdp_csr_n;

    //clocks
    wire clk_108m;
    wire clk_108m_n;
    CLK_108P clk_main (
        .clkout(clk_108m), //output clkout
        .lock(), //output lock
        .clkoutp(clk_108m_n), //output clkoutp
        .reset(0), //input reset
        .clkin(ex_clk_27m) //input clkin
    );

    wire clk_enable_27m;
    wire clk_enable_54m;
    reg [1:0] cnt_clk_enable_27m;
    always @ (posedge clk_108m) begin
        cnt_clk_enable_27m <= cnt_clk_enable_27m + 1;
    end
    assign clk_enable_27m = ( cnt_clk_enable_27m == 2'b00 ) ? 1: 0;
    assign clk_enable_54m = ( cnt_clk_enable_27m[0] == 1 ) ? 1: 0;

    wire clk_27m;
    Gowin_CLKDIV div4(
        .clkout(clk_27m), //output clkout
        .hclkin(clk_108m), //input hclkin
        .resetn(1) //input resetn
    );

    wire bus_clk_3m6;
`ifdef DIAG_AUTOBOOT
    //----------------------------------------------------------------
    //-- Goa'uld Doctor: robust clock.  If the board gives no Z80 clock
    //-- (on an MSX1 it comes from the VDP's CPUCLK pin, so a dead VDP
    //-- or crystal kills it) the core falls back to an internal 3.6 MHz
    //-- (54/15) so the diagnostic ROM can still boot and REPORT it.
    //-- The choice is latched at the end of every internal reset pulse
    //-- (core in reset -> switching is glitch-free), never mid-run.
    //----------------------------------------------------------------
    wire bus_clk_3m6_pin;
    PINFILTER dn1(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_clk_3m6),
        .dout(bus_clk_3m6_pin)
    );
    reg [3:0] diag_iclk_cnt = 4'd0;
    reg       diag_clk_int  = 1'b0;
    always @ (posedge clk_54m) begin
        diag_iclk_cnt <= (diag_iclk_cnt == 4'd14) ? 4'd0 : diag_iclk_cnt + 4'd1;
        diag_clk_int  <= (diag_iclk_cnt < 4'd7);            // 7 high / 8 low
    end
    reg        diag_clk_pin_d   = 1'b0;
    reg [11:0] diag_clk_win     = 12'd0;
    reg        diag_clk_edge    = 1'b0;
    reg        diag_clk_alive   = 1'b0;                     // edge in last 76 us
    always @ (posedge clk_54m) begin
        diag_clk_pin_d <= bus_clk_3m6_pin;
        diag_clk_win   <= diag_clk_win + 12'd1;
        if (diag_clk_pin_d ^ bus_clk_3m6_pin) diag_clk_edge <= 1'b1;
        if (diag_clk_win == 12'hFFF) begin
            diag_clk_alive <= diag_clk_edge;
            diag_clk_edge  <= 1'b0;
        end
    end
    wire diag_reset_n;                                      // defined below
    reg  diag_reset_n_d = 1'b0;
    reg  diag_clk_use_int = 1'b0;
    always @ (posedge clk_54m) begin
        diag_reset_n_d <= diag_reset_n;
        if (diag_reset_n & ~diag_reset_n_d)                 // reset pulse ends
            diag_clk_use_int <= ~diag_clk_alive;
    end
    assign bus_clk_3m6 = diag_clk_use_int ? diag_clk_int : bus_clk_3m6_pin;
`else
    PINFILTER dn1(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_clk_3m6),
        .dout(bus_clk_3m6)
    );
`endif
    reg bus_clk_3m6_27;
//    CLOCK_DIV #(
//        .CLK_SRC(54.0),
//        .CLK_DIV(15.0),
//        .PRECISION_BITS(16)
//    ) cpuclkd (
//        .clk_src(clk_54m),
//        .clk_div(bus_clk_3m6)
//    );

    reg bus_clk_3m6_27;
    reg bus_clk_3m6_27_0;
    reg bus_clk_3m6_27_1;
    reg bus_clk_3m6_27_2;
    reg bus_clk_3m6_27_3;
    reg bus_clk_3m6_27_4;
    reg bus_clk_3m6_27_5;
    reg bus_clk_3m6_27_6;

    always @ (posedge clk_27m) begin
        bus_clk_3m6_27_6 <= bus_clk_3m6;
        bus_clk_3m6_27_5 <= bus_clk_3m6_27_6;
        bus_clk_3m6_27_4 <= bus_clk_3m6_27_5;
        bus_clk_3m6_27_3 <= bus_clk_3m6_27_4;
        bus_clk_3m6_27_2 <= bus_clk_3m6_27_3;
        bus_clk_3m6_27_1 <= bus_clk_3m6_27_2;
        bus_clk_3m6_27_0 <= bus_clk_3m6_27_1;
        bus_clk_3m6_27 <= bus_clk_3m6_27_0;
    end

    wire clk_enable_3m6_27;
    wire clk_falling_3m6_27;
    reg bus_clk_3m6_prev_27;
    always @ (posedge clk_27m) begin
        bus_clk_3m6_prev_27 <= bus_clk_3m6_27;
    end
    assign clk_enable_3m6_27 = (bus_clk_3m6_prev_27 == 0 && bus_clk_3m6_27 == 1);
    assign clk_falling_3m6_27 = (bus_clk_3m6_prev_27 == 1 && bus_clk_3m6_27 == 0);

    wire clk_54m;
    Gowin_CLKDIV2 div2(
        .clkout(clk_54m), //output clkout
        .hclkin(clk_108m), //input hclkin
        .resetn(1) //input resetn
    );

    wire clk_enable_3m6_54;
    wire clk_falling_3m6_54;
    reg bus_clk_3m6_54;
    reg bus_clk_3m6_prev_54;
    always @ (posedge clk_54m) begin
        bus_clk_3m6_54 <= bus_clk_3m6;
        bus_clk_3m6_prev_54 <= bus_clk_3m6_54;
    end
    assign clk_enable_3m6_54 = (bus_clk_3m6_54 == 0 && bus_clk_3m6 == 1);
    assign clk_falling_3m6_54 = (bus_clk_3m6_54 == 1 && bus_clk_3m6 == 0);

    wire bus_wait_n;
    PINFILTER dn2(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_wait_n),
        .dout(bus_wait_n)
    );

    wire bus_reset_n;
`ifdef DIAG_AUTOBOOT
    //----------------------------------------------------------------
    //-- Goa'uld Doctor: robust reset.  The board's /RESET is treated as
    //-- EDGE-sensitive: a falling edge produces a ~10 ms internal reset
    //-- pulse, and the FPGA config itself produces one (power-on).  A
    //-- /RESET stuck low therefore does NOT hold the core in reset - it
    //-- is only reported (SYS_STAT bit2 / RST_EDGES) by the diagnostic.
    //----------------------------------------------------------------
    wire ex_reset_n_f;
    PINFILTER dn3a(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_reset_n),
        .dout(ex_reset_n_f)
    );
    reg        ex_reset_n_d   = 1'b0;            // 0: no false edge at config
    reg [19:0] diag_rst_cnt   = 20'd0;           // counts up to 2^19 = 9.7 ms
    reg [7:0]  diag_rst_edges = 8'd0;
    always @ (posedge clk_54m) begin
        ex_reset_n_d <= ex_reset_n_f;
        if (ex_reset_n_d & ~ex_reset_n_f) begin  // falling edge on the pin
            diag_rst_cnt <= 20'd0;
            if (diag_rst_edges != 8'hFF) diag_rst_edges <= diag_rst_edges + 8'd1;
        end
        else if (!diag_rst_cnt[19])
            diag_rst_cnt <= diag_rst_cnt + 20'd1;
    end
    assign diag_reset_n = diag_rst_cnt[19];
    PINFILTER dn3(
        .clk(clk_54m),
        .reset_n(1),
        .din(diag_reset_n & ~config_reset),
        .dout(bus_reset_n)
    );
`else
    PINFILTER dn3(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_reset_n & ~config_reset),
        .dout(bus_reset_n)
    );
`endif

    wire bus_int_n;
//    PINFILTER dn4(
//        .clk(clk_108m),
//        .reset_n(1),
//        .din(ex_bus_int_n),
//        .dout(bus_int_n)
//    );
    denoise dn4 (
		.data_in (ex_bus_int_n),
		.clock(clk_54m),
		.data_out (bus_int_n)
    );

    reg [7:0] bus_data;
    genvar i;
    generate
        for (i = 0; i <= 7; i++)
        begin: bus_din
            PINFILTER dn(
                .clk(clk_54m),
                .reset_n(1),
                .din(ex_bus_data[i]),
                .dout(bus_data[i])
            );
//            denoise2 dn (
//                .data_in (ex_bus_data[i]),
//                .clock(clk_108m),
//                .data_out (bus_data[i])
//            );
        end
    endgenerate

//    always @ (posedge clk_108m) begin
//        bus_data <= ex_bus_data;
//    end

    //startup logic
    reg reset1_n_ff;
    reg reset2_n_ff;
    reg reset3_n_ff;
    wire reset1_n;
    wire reset2_n;
    wire reset3_n;

    reg [20:0] counter_reset = 0;
    reg [1:0] rst_seq;
    reg rst_step;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
            rst_step <= 0;
            counter_reset <= 0;
        end
        else begin
            rst_step <= 0;
            if ( counter_reset <= 21'b100000000000000000000 ) 
                counter_reset <= counter_reset + 1;
            else begin
                rst_step <= 1;
                counter_reset <= 0;
            end
        end
    end

    always @ (posedge clk_27m or negedge bus_reset_n ) begin
        if (bus_reset_n == 0 ) begin
            rst_seq <= 2'b00;
            reset1_n_ff <= 0;
            reset2_n_ff <= 0;
            reset3_n_ff <= 0;
        end
        else begin
            case ( rst_seq )
                2'b00: 
                    if (rst_step == 1 ) begin
                        reset1_n_ff <= 1;
                        rst_seq <= 2'b01;
                    end
                2'b01: 
                    if (rst_step == 1) begin
                        reset2_n_ff <= 1;
                        rst_seq <= 2'b10;
                    end
                2'b10:
                    if (rst_step == 1) begin
                        reset3_n_ff <= 1;
                        rst_seq <= 2'b11;
                    end
            endcase
        end
    end
    assign reset1_n = reset1_n_ff;
    assign reset2_n = reset2_n_ff;
    assign reset3_n = reset3_n_ff;

    //bus demux
    reg [1:0] msel;
    reg [7:0] bus_mp;
    reg [4:0] mp_cnt;
    wire [15:0] bus_addr;
    assign ex_msel = msel;
    assign ex_bus_mp = bus_mp;

    localparam IDLE = 2'd0;
    localparam LATCH = 2'd1;
    localparam FINISH1 = 2'd3;
    localparam FINISH2 = 2'd2;
    localparam [3:0] TON = 4'd3;
    localparam [3:0] TP = 4'd1; //prefetch time
    reg [1:0] state_demux;
    reg [3:0] counter_demux;
    reg low_byte_demux;
    wire update_demux;
    assign bus_mp = ( low_byte_demux == 0 ) ? bus_addr[15:8] : bus_addr[7:0];
    always @ (posedge clk_108m) begin
        if (~bus_reset_n) begin
            state_demux <= LATCH;
            counter_demux <= 4'd0;
            low_byte_demux <= 0;
        end 
        else begin
            counter_demux = counter_demux + 4'd1;
            casex ({state_demux, counter_demux})
                {IDLE, 4'bxxxx}: begin
                    msel <= 2'b00;
                    counter_demux <= 4'd0;
                    low_byte_demux <= 0;
                    if (update_addr == 1 ) begin
                        state_demux <= LATCH;
                    end
                end
                {LATCH, 4'd1} : begin
                    msel[1] <= 1;
                end
                {LATCH, 4'd1 + TON} : begin
                    msel[1] <= 0;
                end
                {LATCH, 4'd1 + TON + TP} : begin
                    low_byte_demux <= 1;
                end
                {LATCH, 4'd1 + TON + TP + TP} : begin
                    msel[0] <= 1;
                end
                {LATCH, 4'd1 + TON + TP + TP + TON} : begin
                    msel[0] <= 0;
                    msel[1] <= 0;
                    state_demux <= FINISH1;
                end
                {FINISH1, 4'bxxxx}: begin
                    if (update_addr == 0 ) begin
                        state_demux <= IDLE;
                    end
                end
                {FINISH2, 4'bxxxx}: begin
                    if (update_addr == 0 ) begin
                        state_demux <= IDLE;
                    end
                end
            endcase
        end
    end




    //bus isolation
    wire bus_data_reverse;
    wire bus_m1_n;
    wire bus_mreq_n;
    wire bus_iorq_n;
    wire bus_rd_n;
    wire bus_wr_n;
    wire bus_rfsh_n;
    reg [7:0] cpu_din;
    wire [7:0] cpu_dout;
    wire bus_mreq_disable;
    wire bus_iorq_disable;
    wire bus_disable;
    assign ex_bus_m1_n = bus_m1_n;
    assign ex_bus_rfsh_n = bus_rfsh_n;
    assign ex_bus_data_reverse_n = ~ bus_data_reverse;
    //assign ex_bus_data_reverse = bus_data_reverse;
    //assign ex_bus_mreq_n = bus_mreq_n;
    //assign ex_bus_iorq_n = bus_iorq_n;
    //assign ex_bus_rd_n = bus_rd_n;
    //assign ex_bus_wr_n = bus_wr_n;

`ifdef DIAG_AUTOBOOT
    //----------------------------------------------------------------
    //-- Goa'uld Doctor control bits (bus_monitor CONTROL register 0x20)
    //--   diag_slot0_ext : physical primary slot 0 of the board is read
    //--                    through the bus (board BIOS / board RAM tests)
    //--   diag_vdp_ext   : VDP I/O 0x98-0x9B goes to the board's own VDP
    //--                    (internal V9958 deselected, reads from the bus)
    //--   diag_ign_int / diag_ign_wait : mask the external lines to the core
    //--   diag_ppi_ext   : IN 0xA8 returns the board's real PPI latch
    //--   diag_kbd_usb_off / diag_kbd_phys_off : drop one keyboard source from
    //--                    the IN 0xA9 merge (a noisy one would fake key presses)
    //--   diag_rtc_ext   : IN 0xB5 returns the board's RTC (RP5C01) instead
    //--                    of the internal one (writes reach both anyway)
    //----------------------------------------------------------------
    //--   diag_trans[3:0] : transparency mask per primary slot (CONTROL2);
    //--                    slot 0 also honours the old slot0_ext bit
    //--   diag_p3_release : hand the internal mapper's 3-0 page 3 to the bus too
    wire diag_ctl_slot0, diag_vdp_ext, diag_ign_int, diag_ign_wait, diag_ppi_ext, diag_rtc_ext;
    wire diag_kbd_usb_off, diag_kbd_phys_off;
    wire [3:0] diag_trans;
    wire diag_p3_release;
    wire diag_wait_stuck;
    wire diag_slot0_ext = diag_ctl_slot0 | diag_trans[0];
    wire diag_slot3_ext = diag_trans[3];
`else
    wire diag_slot0_ext = 1'b0, diag_vdp_ext = 1'b0, diag_ign_int = 1'b0;
    wire diag_ign_wait = 1'b0, diag_ppi_ext = 1'b0, diag_wait_stuck = 1'b0, diag_rtc_ext = 1'b0;
    wire diag_kbd_usb_off = 1'b0, diag_kbd_phys_off = 1'b0;
    wire diag_slot3_ext = 1'b0, diag_p3_release = 1'b0;
`endif

    assign bus_mreq_disable = 0;
    assign bus_iorq_disable = (
                                0
                        `ifdef ENABLE_V9958
                                || ((vdp_csr_n == 0 || vdp_csw_n == 0) && diag_vdp_ext == 0)
                        `endif
                                ) ? 1 : 0;

    assign bus_disable = bus_mreq_disable | bus_iorq_disable;
//    assign ex_bus_data = ( bus_data_reverse == 1 && slot0_req_w == 0 ) ? cpu_dout : 
//                         ( slot0_req_w == 1 ) ? 8'hff :  8'hzz;
`ifndef SWAP23
    assign ex_bus_data =  ( bus_data_reverse == 1 ) ? cpu_dout : 8'hzz;
`else

    function [1:0] swap;
        input [1:0] entrada;
        begin
            case (entrada)
                2'b00: swap = 2'b00;
                2'b01: swap = 2'b01;
                2'b10: swap = 2'b11;
                2'b11: swap = 2'b10;
                default: swap = 2'b00; // Por seguridad
            endcase
        end
    endfunction

    wire [7:0] cpu_dout_swap;
    assign cpu_dout_swap = { swap(cpu_dout[7:6]), swap(cpu_dout[5:4]), swap(cpu_dout[3:2]), swap(cpu_dout[1:0]) };

    reg ppi_swap;
    always @ (posedge clk_27m) begin
        if (~bus_reset_n) begin
            ppi_swap <= 0;
        end
        else begin
            if (ppi_swap == 0) begin
                if (bus_data_reverse == 1  && ppi_req_w == 1) begin
                    ppi_swap <= 1;
                end
            end
            else begin
                if (bus_data_reverse == 0) begin
                    ppi_swap <= 0;
                end
            end
        end
    end

    assign ex_bus_data =  ( bus_data_reverse == 1  && ppi_swap == 0) ? cpu_dout : 
                          ( bus_data_reverse == 1  && ppi_swap == 1) ? cpu_dout_swap : 8'hzz;
`endif

    always @ (posedge clk_54m) begin
        cpu_din <=
                `ifdef ENABLE_V9958
                     ( vdp_csr_n == 0) ? (diag_vdp_ext ? bus_data : vdp_dout) :
                `endif
`ifdef DIAG_AUTOBOOT
                     // Doctor: physical slot 3 transparent (board RAM/ROM in
                     // any 3-x), keeping the internal mapper's 3-0 page 3
                     // (our stack + BIOS work area) unless p3_release
                     ( diag_slot3_ext == 1 && slotx_req_r == 1 &&
                       !(exp_slotx_num[0] == 1 && page_num[3] == 1 && diag_p3_release == 0) ) ? bus_data :
`endif
                `ifdef ENABLE_MAPPER
                     ( mapper_read == 1) ? ram_dout :
                `endif
                `ifdef ENABLE_BIOS
                     ( exp_slot0_req_r == 1) ? ~exp_slot0  :
                     ( exp_slotx_req_r == 1) ? ~exp_slotx  :
`ifdef DIAG_AUTOBOOT
                     // Doctor ROM (slot 0-3 page 1) always wins, then the rest
                     // of physical slot 0 becomes transparent to the board
                     // (board BIOS 0000-7FFF via subslot 0, board RAM pages 2/3)
                     ( diag_req == 1) ? diag_dout :
                     ( diag_slot0_ext == 1 && slot0_req_r == 1 ) ? bus_data :
`endif
                     ( bios_req == 1) ? ram_dout :
                     ( subrom_logo_req == 1 ) ? ram_dout :
                `endif
                `ifdef ENABLE_SDCARD
                     ( sd_busreq_w == 1) ? sd_cd_w :
                     ( sram_busreq_w == 1) ? sram_cd_w :
                     ( megarom_req == 1) ? ram_dout :
                     //( slot3_req_r == 1) ? 8'hff :
                 `endif
                `ifdef ENABLE_SOUND
                     //( scc_req3_r == 1 ) ? scc_dout:
                     ( megaram_req == 1 ) ? ram_dout:
                `endif
                `ifdef ENABLE_CONFIG
                     ( config_req == 1 && config_ok == 1) ? config_dout :
                     ( config_req == 1 && config_ok == 0) ? swio_dout :
                `endif
                     ( kanji_driver_req == 1 ) ? ram_dout :
                     ( kanji_data_req_r == 1 ) ? ram_dout :
                `ifdef ENABLE_WIFI
                     ( wifi_req == 1 ) ? ram_dout :
                     ( f2_req_r == 1 ) ? f2_port :
                     ( uart_req == 1 ) ? uart_dout :
                `endif
                     ( rtc_req_r == 1 && diag_rtc_ext == 0 ) ? rtc_dout :
                     ( ppi_req_r == 1 && diag_ppi_ext == 0 ) ? ppi_port_a :
                     ( slot0_req_r == 1 ) ? 8'hff :
                     ( slotx_req_r == 1 ) ? 8'hff :
`ifndef DIAG_SLIM
                     // Version guard reads (see the 0x2E/0x2F block by the PSG merge)
                     ( ver_fpga_req_r ) ? FPGA_VERSION :
                     ( ver_sel_req_r  ) ? ver_sel_dout :
`endif
                     // USB-keyboard merge: on an I/O 0xA9 keyboard-column read,
                     // AND the physical PPI read (bus_data) with the virtual
                     // matrix row. Both are active-low, so a key pressed on
                     // EITHER keyboard pulls its bit to 0.
                     // USB-joystick merge: on a PSG reg-14 read (I/O 0xA2 while
                     // reg 14 is selected), AND the real MSX joystick read
                     // (bus_data) with the USB joystick. Both active-low, so a
                     // direction/button on EITHER pad pulls its bit to 0.
                     // All other reads fall through to bus_data unchanged.
                     ( kbd_a9_req_r ) ? ((bus_data | {8{diag_kbd_phys_off}}) & (vkey_row | {8{diag_kbd_usb_off}})) :
                     ( psg_a2_reg14_req_r ) ? (bus_data & psg_joy_inject) :
                     ( busmon_dat_re ) ? busmon_dout :
                     bus_data;
    end


//    wire ex_bus_rd_n_test;
//    wire ex_bus_wr_n_test;
//    wire ex_bus_iorq_n_test;
//    wire ex_bus_mreq_n_test;
    reg ex_bus_rd_n_ff;
    reg ex_bus_wr_n_ff;
    reg ex_bus_iorq_n_ff;
    reg ex_bus_mreq_n_ff;
    localparam IDLE_ISO = 2'd0;
    localparam ACTIVE_ISO = 2'd1;
    localparam WAIT_ISO = 2'd2;
    reg [1:0] state_iso;
    reg [2:0] counter_iso;
    wire io_active;

    //assign ex_bus_rd_n = ( bus_rd_n | ex_bus_rd_n_ff | bus_disable);
    assign ex_bus_rd_n = bus_rd_n;
    //assign ex_bus_wr_n = ( bus_wr_n | ex_bus_wr_n_ff | bus_disable);
    assign ex_bus_wr_n = bus_wr_n;
    assign ex_bus_iorq_n = ( bus_iorq_n | bus_iorq_disable );
    assign ex_bus_mreq_n = ( bus_mreq_n | bus_mreq_disable );
    assign io_active = ( state_iso != IDLE_ISO ) ? 1 : 0;

    always @ ( posedge clk_108m ) begin
        if (~bus_reset_n) begin
            state_iso <= IDLE_ISO;
            ex_bus_rd_n_ff <= 1;
            ex_bus_wr_n_ff <= 1;
        end 
        else begin
            counter_iso = counter_iso + 3'd1;
            casex ({state_iso, counter_iso})
                {IDLE_ISO, 3'bxxx}: begin
                    ex_bus_rd_n_ff <= 1;
                    ex_bus_wr_n_ff <= 1;
                    counter_iso <= 3'd0;
                    if (bus_rd_n == 0 || bus_wr_n == 0 ) begin
                        state_iso <= ACTIVE_ISO;
                    end
                end
                {ACTIVE_ISO, 3'd2} : begin
                    ex_bus_rd_n_ff <= bus_rd_n;
                    ex_bus_wr_n_ff <= bus_wr_n;
                    state_iso <= WAIT_ISO;
                end
                {WAIT_ISO, 3'bxxx} : begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1 ) begin
                        state_iso <= IDLE_ISO;
                    end
                end
            endcase
        end
    end

`ifdef ENABLE_WAIT
    wire wait_io;
    reg wait_io_ff = 1;
    reg [6:0] wait_cycles;
    reg [6:0] state_wait;
    localparam WAIT_IDLE = 7'd0;
    localparam WAIT_STATE1 = 7'd1;
    localparam WAIT_STATE2 = 7'd3;
    localparam WAIT_STATE3 = 7'd2;
    localparam WAIT_STATE4 = 7'd4;

    assign wait_io = wait_io_ff;

  `ifndef ENABLE_WAIT_ADAPTIVE
    wire wait_iorq_n = ex_bus_iorq_n;
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            state_wait <= WAIT_IDLE;
            wait_io_ff <= 1;
        end 
        else begin
            case (state_wait)
                WAIT_IDLE: begin
                    if ( ram_write == 1 || (wait_iorq_n == 0 || ( config_enable_wait == 1 && ex_bus_mreq_n == 0 ) )&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin
                        wait_io_ff <= 0;
                        state_wait <= WAIT_STATE1;
                    end
                end
                WAIT_STATE1: begin
                    if ( clk_enable_3m6_54 == 1 ) begin
                        state_wait <= WAIT_STATE2;
                    end
                end
                WAIT_STATE2: begin
                    if ( clk_falling_3m6_54 == 1 ) begin
                        wait_io_ff <= 1;
                        state_wait <= WAIT_STATE3;
                    end
                end
                WAIT_STATE3: begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1) begin
                        state_wait <= WAIT_IDLE;
                    end
                end
            endcase
        end
    end
  `else
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            state_wait <= WAIT_IDLE;
            wait_io_ff <= 1;
        end 
        else begin
            case (state_wait)
                WAIT_IDLE: begin
                    if ( (ex_bus_iorq_n == 0 || bus_mreq_n == 0 ) && (bus_rd_n == 0 || bus_wr_n == 0) ) begin
                        wait_io_ff <= 0;
                        wait_cycles <= 7'd6;
                        state_wait <= WAIT_STATE1;
                    end
                end
                WAIT_STATE1: begin
                    wait_cycles <= wait_cycles - 1;
                    if ( wait_cycles == 0 ) begin
                        state_wait <= WAIT_STATE2;
                    end
                end
                WAIT_STATE2: begin
                    if ( ram_busy == 0 && clk_enable_3m6_54 == 1 ) begin
                        state_wait <= WAIT_STATE3;
                    end
                end
                WAIT_STATE3: begin
                    if ( clk_falling_3m6_54 == 1 ) begin
                        wait_io_ff <= 1;
                        state_wait <= WAIT_STATE4;
                    end
                end
                WAIT_STATE4: begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1) begin
                        state_wait <= WAIT_IDLE;
                    end
                end
            endcase
        end
    end
  `endif

`endif

    wire update_addr;
    G80a  #(
        .Mode    (0),     // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        //.T2Write (0),     //0 => WR_n active in T3, /=0 => WR_n active in T2
        .IOWait   (1)      // 0 => Single I/O cycle, 1 => Std I/O cycle
    ) cpu1 (
        .RESET_n   (bus_reset_n & reset3_n & flash_idle),
        .CLK_n     (clk_54m),
    `ifdef ENABLE_WAIT
        .clk_enable (clk_enable_3m6_54 & wait_io ),
        .clk_falling (clk_falling_3m6_54 & wait_io ),
    `else
        .clk_enable (clk_enable_3m6_54),
		.clk_falling (clk_falling_3m6_54),
    `endif
    `ifdef ENABLE_WIFI
      `ifndef ENABLE_WAIT_ADAPTIVE
        .WAIT_n    ((bus_wait_n | diag_ign_wait | diag_wait_stuck) & wait_uart),
      `else
        .WAIT_n    (wait_uart),
      `endif
    `else
      `ifndef ENABLE_WAIT_ADAPTIVE
        .WAIT_n    (bus_wait_n | diag_ign_wait | diag_wait_stuck),
      `else
        .WAIT_n    (1),
      `endif
    `endif
    `ifdef ENABLE_V9958
        // Doctor: external /INT maskable; internal VDP int held off while the
        // VDP ports are routed to the board (its status is not being read).
        .INT_n     ((bus_int_n | diag_ign_int) & (vdp_int | diag_vdp_ext)),
    `else
        .INT_n     (bus_int_n | diag_ign_int),
    `endif
        .NMI_n     (1),
        .BUSRQ_n   (1),
        .M1_n      (bus_m1_n),
        .MREQ_n    (bus_mreq_n),
        .IORQ_n    (bus_iorq_n),
        .RD_n      (bus_rd_n),
        .WR_n      (bus_wr_n),
        .RFSH_n    (bus_rfsh_n),
        .HALT_n    ( ),
        .BUSAK_n   ( ),
        .A         (bus_addr),
        .update_addr(update_addr),
        .DI         (cpu_din),
        .DO         (cpu_dout),
        .Data_Reverse (bus_data_reverse)
    );

    //slots decoding
    reg [7:0] ppi_port_a = 8'h00;
    wire ppi_req_r;
    wire ppi_req_w;
    wire [1:0] pri_slot;
    wire [3:0] pri_slot_num;
    wire [3:0] page_num;

    //----------------------------------------------------------------
    //-- PPI(8255) / primary-slot
    //----------------------------------------------------------------
    assign ppi_req_r = (bus_addr[7:0] == 8'ha8 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign ppi_req_w = (bus_addr[7:0] == 8'ha8 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;

    //----------------------------------------------------------------
    //-- bus_monitor I/O port decodes (IDX=0x2C, DAT=0x2D)
    //--   0x2C/0x2D chosen: free on MSX and NOT decoded by the Goa'uld.
    //--   (0x40-0x4F is taken by config/OCM switched-I/O at l.468/1617/2175,
    //--    which sit higher in the cpu_din mux and would shadow this read.)
    //----------------------------------------------------------------
    wire        busmon_idx_we = (bus_addr[7:0]==8'h2C && bus_iorq_n==0 && bus_m1_n==1 && bus_wr_n==0);
    wire        busmon_dat_re = (bus_addr[7:0]==8'h2D && bus_iorq_n==0 && bus_m1_n==1 && bus_rd_n==0);
    wire        busmon_dat_we = (bus_addr[7:0]==8'h2D && bus_iorq_n==0 && bus_m1_n==1 && bus_wr_n==0);
    wire [7:0]  busmon_dout;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            ppi_port_a <= 8'h00;
        else begin
            if (ppi_req_w == 1 ) begin
                ppi_port_a <= cpu_dout;
            end
        end
    end

    //----------------------------------------------------------------
    //-- USB keyboard (virtual matrix fed by UART from RP2040)
    //--   PPI port C (I/O 0xAA) write selects the keyboard column; we
    //--   latch its low nibble (bits 3:0) as the active matrix column.
    //--   PPI port B (I/O 0xA9) read returns the column's row state; we
    //--   merge the FPGA virtual matrix row with the physical read in the
    //--   cpu_din mux above via active-low AND, so both keyboards work.
    //--   This logic only OBSERVES the bus and supplies vkey_row; it never
    //--   drives the data bus on reads.
    //----------------------------------------------------------------
    wire ppi_c_req_w = (bus_addr[7:0] == 8'haa && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0);
    reg [3:0] vkey_col;
    always @(posedge clk_54m or negedge bus_reset_n)
        if (!bus_reset_n) vkey_col <= 4'd0;
        else if (ppi_c_req_w) vkey_col <= cpu_dout[3:0];

    wire kbd_a9_req_r = (bus_addr[7:0] == 8'ha9 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0);
    wire [7:0] vkey_row;

    //----------------------------------------------------------------
    //-- USB joystick (virtual, fed by UART from RP2040 via kbd_uart_rx)
    //--   The MSX reads joysticks through the PSG: I/O 0xA0 selects the
    //--   register, 0xA1 writes it, 0xA2 reads it. Our internal PSG is
    //--   audio-only (its data output is unconnected), so the joystick read
    //--   at 0xA2 (PSG reg 14) is served by the REAL MSX over the external
    //--   bus and falls through the cpu_din mux to bus_data. We snoop the
    //--   PSG register select (0xA0 write) and the port-select bits in PSG
    //--   reg 15 (0xA1 write, bits[7:6], active-low), then AND-merge the USB
    //--   joystick into the 0xA2/reg14 read so BOTH the real MSX joystick and
    //--   the USB joystick work simultaneously. This block only OBSERVES the
    //--   bus; it never drives the data bus. All in clk_54m.
    //----------------------------------------------------------------
    // Latch the PSG register number written via I/O 0xA0.
    reg [3:0] psg_addr_latch;
    always @(posedge clk_54m or negedge bus_reset_n)
        if (!bus_reset_n) psg_addr_latch <= 4'd0;
        else if (bus_addr[7:0] == 8'hA0 && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1)
            psg_addr_latch <= cpu_dout[3:0];

    // PSG reg 15 (Port B) write: bits[7:6] select the joystick port (active-low).
    // bit6=0 -> port 1 (joy0), bit7=0 -> port 2 (joy1).
    reg [1:0] psg_reg15_joy_sel;
    always @(posedge clk_54m or negedge bus_reset_n)
        if (!bus_reset_n) psg_reg15_joy_sel <= 2'b11;
        else if (bus_addr[7:0] == 8'hA1 && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1
                 && psg_addr_latch == 4'd15)
            psg_reg15_joy_sel <= cpu_dout[7:6];

    // True during a PSG reg-14 read (I/O 0xA2 read while reg 14 is selected).
    wire psg_a2_reg14_req_r = (bus_addr[7:0] == 8'hA2 && bus_iorq_n == 0 && bus_m1_n == 1
                               && bus_rd_n == 0 && psg_addr_latch == 4'd14);

    // USB joystick state from the UART receiver (active-high as received).
    wire [7:0] joy_usb0;
    wire [7:0] joy_usb1;

    // Remap active-high USB byte (bit0=R,1=L,2=D,3=U,4=A,5=B) to the MSX PSG
    // Port A active-low layout (bit0=Up,1=Down,2=Left,3=Right,4=TrigA,5=TrigB).
    wire [7:0] joy0_msx = {2'b11, ~joy_usb0[5], ~joy_usb0[4], ~joy_usb0[0], ~joy_usb0[1], ~joy_usb0[2], ~joy_usb0[3]};
    wire [7:0] joy1_msx = {2'b11, ~joy_usb1[5], ~joy_usb1[4], ~joy_usb1[0], ~joy_usb1[1], ~joy_usb1[2], ~joy_usb1[3]};

    // Select the merged value for the currently-selected port; if neither port
    // is selected, present all-released (0xFF) so the AND-merge is transparent.
    wire [7:0] psg_joy_inject = (!psg_reg15_joy_sel[0]) ? joy0_msx :
                                (!psg_reg15_joy_sel[1]) ? joy1_msx :
                                8'hFF;

    //----------------------------------------------------------------
    //-- Version guard (I/O 0x2E/0x2F) -- keeps the three flashables in step.
    //--   All three artifacts carry the SAME BCD version (0x12 = v1.2):
    //--     .fs  = FPGA_VERSION below;
    //--     .uf2 = announced by the RP2040 as 0xC0 <ver> with every 250 ms
    //--            resync (fw_version from kbd_uart_rx; 0x00 = link down);
    //--     .bin = LAST byte of the 512KB BIOS pack (flash 0x27FFFF), latched
    //--            by the flash loader FSM while it streams the pack at boot.
    //--   Reads (never driven onto the external bus, cpu_din substitution only):
    //--     IN 0x2F          -> FPGA_VERSION
    //--     OUT 0x2F,n       -> select what IN 0x2E returns:
    //--     IN 0x2E (n=0)    -> RP2040 firmware version (0x00 = not announced)
    //--     IN 0x2E (n=1)    -> BIOS pack version byte  (0xFF = pre-v1.2 pack)
    //--     IN 0x2E (n=2)    -> verify status: 0x00 = ALL MATCH, else
    //--                         bit0 uf2 mismatch, bit1 uf2 not announced,
    //--                         bit2 pack mismatch, bit3 pack has no version
    //--   BASIC check:  OUT &H2F,2 : IF INP(&H2E)=0 THEN PRINT"OK"
    //--   Same 0x2F convention as MSXnano (0x19 = v1.9). Note: the separate
    //--   bus-monitor diagnostic bitstream uses 0x2C/0x2D -- no overlap.
    //--   Caveat: reads of 0x2E/0x2F shadow the S-1985 engine test registers
    //--   on machines that have one (writes still reach the real bus).
    //----------------------------------------------------------------
    localparam [7:0] FPGA_VERSION = 8'h12;   // v1.2 -- bump together with FW_VERSION (usbin.h) and the pack byte
`ifndef DIAG_SLIM

    wire [7:0] kbd_fw_version;               // from kbd_uart_rx (0xC0 announce)

    // OUT 0x2F latches the read-index for 0x2E.
    reg [1:0] ver_index;
    always @(posedge clk_54m or negedge bus_reset_n)
        if (!bus_reset_n) ver_index <= 2'd0;
        else if (bus_addr[7:0] == 8'h2F && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1)
            ver_index <= cpu_dout[1:0];

    wire ver_fpga_req_r = (bus_addr[7:0] == 8'h2F && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0);
    wire ver_sel_req_r  = (bus_addr[7:0] == 8'h2E && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0);

    // The FPGA does the verification: 0x00 = everything matches.
    wire [7:0] ver_status = { 4'b0000,
                              (ff_pack_version == 8'hFF || ff_pack_version == 8'h00), // bit3: pack has no version byte
                              (ff_pack_version != FPGA_VERSION),                      // bit2: pack mismatch
                              (kbd_fw_version  == 8'h00),                             // bit1: uf2 not announced / link down
                              (kbd_fw_version  != FPGA_VERSION) };                    // bit0: uf2 mismatch

    wire [7:0] ver_sel_dout = (ver_index == 2'd0) ? kbd_fw_version  :
                              (ver_index == 2'd1) ? ff_pack_version :
                              (ver_index == 2'd2) ? ver_status      : FPGA_VERSION;

    // Red-border warning: assert ONLY on stable, real mismatches -- a loaded pack
    // whose version differs (incl. 0xFF pre-v1.2 packs) or an ANNOUNCED uf2 whose
    // version differs. Excludes 0x00 (pack not yet loaded at boot; RP2040 optional
    // / not announced) so there is no false red at boot and none without a Pico.
    wire version_mismatch = (ff_pack_version != 8'h00 && ff_pack_version != FPGA_VERSION) ||
                            (kbd_fw_version  != 8'h00 && kbd_fw_version  != FPGA_VERSION);
`else
    wire version_mismatch = 1'b0;           // Doctor: no version guard, no red border
`endif

    //expanded slots 0 & 3
    reg [7:0] exp_slot0;
    wire [1:0] exp_slot0_page;
    wire [3:0] exp_slot0_num;
    reg exp_slot0_req_r;
    reg exp_slot0_req_w;
    reg [7:0] exp_slotx;
    wire [1:0] exp_slotx_page;
    wire [3:0] exp_slotx_num;
    reg exp_slotx_req_r;
    reg exp_slotx_req_w;
    wire xffff;
    reg xffh;
    reg xffl;
    always @ (posedge clk_54m) begin
        xffh <= bus_addr[15:8] == 8'hff;
        xffl <= bus_addr[7:0] == 8'hff;
        exp_slot0_req_w <= ( bus_mreq_n == 0 && bus_wr_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
        exp_slot0_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
        exp_slotx_req_w <= ( bus_mreq_n == 0 && bus_wr_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[SD_SLOT] == 1 ) ? 1: 0;
        exp_slotx_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[SD_SLOT] == 1 ) ? 1: 0;
    end
    //assign xffff = ( bus_addr == 16'hffff ) ? 1 : 0;
    assign xffff = xffh & xffl;

//    assign exp_slotx_req_w = ( bus_mreq_n == 0 && bus_wr_n == 0 && xffff == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
//    assign exp_slotx_req_r = ( bus_mreq_n == 0 && bus_rd_n == 0 && xffff == 1 && pri_slot_num[0] == 1 ) ? 1: 0;

    // slot #0
    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0 )
            exp_slot0 <= 8'h00;
        else begin
            if (exp_slot0_req_w == 1 ) begin
                exp_slot0 <= cpu_dout;
            end
        end
    end

    // slot #3
    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0 )
            exp_slotx <= 8'h00;
        else begin
            if (exp_slotx_req_w == 1 ) begin
                exp_slotx <= cpu_dout;
            end
        end
    end

    // slots decoding
    assign pri_slot = ( bus_addr[15:14] == 2'b00) ? ppi_port_a[1:0] :
                      ( bus_addr[15:14] == 2'b01) ? ppi_port_a[3:2] :
                      ( bus_addr[15:14] == 2'b10) ? ppi_port_a[5:4] :
                                             ppi_port_a[7:6];

    assign pri_slot_num = ( pri_slot == 2'b00 ) ? 4'b0001 :
                          ( pri_slot == 2'b01 ) ? 4'b0010 :
                          ( pri_slot == 2'b10 ) ? 4'b0100 :
                                                  4'b1000;

    assign page_num = ( bus_addr[15:14] == 2'b00) ? 4'b0001 :
                      ( bus_addr[15:14] == 2'b01) ? 4'b0010 :
                      ( bus_addr[15:14] == 2'b10) ? 4'b0100 :
                                                    4'b1000;
    assign exp_slot0_page = ( bus_addr[15:14] == 2'b00) ? exp_slot0[1:0] :
                            ( bus_addr[15:14] == 2'b01) ? exp_slot0[3:2] :
                            ( bus_addr[15:14] == 2'b10) ? exp_slot0[5:4] :
                                                          exp_slot0[7:6];

    assign exp_slot0_num = ( exp_slot0_page == 2'b00 ) ? 4'b0001 :
                           ( exp_slot0_page == 2'b01 ) ? 4'b0010 :
                           ( exp_slot0_page == 2'b10 ) ? 4'b0100 :
                                                         4'b1000;

    assign exp_slotx_page = ( bus_addr[15:14] == 2'b00) ? exp_slotx[1:0] :
                            ( bus_addr[15:14] == 2'b01) ? exp_slotx[3:2] :
                            ( bus_addr[15:14] == 2'b10) ? exp_slotx[5:4] :
                                                          exp_slotx[7:6];

    assign exp_slotx_num = ( exp_slotx_page == 2'b00 ) ? 4'b0001 :
                           ( exp_slotx_page == 2'b01 ) ? 4'b0010 :
                           ( exp_slotx_page == 2'b10 ) ? 4'b0100 :
                                                         4'b1000;

    reg slot0_req_r;
    reg slotx_req_r;
    always @ (posedge clk_54m) begin
        slot0_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1 ) ? 1 : 0;
        slotx_req_r <= ( ( config_enable_mapper3 == 1 || config_enable_megaram3 == 1 || config_enable_sdcard == 1 ) && bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 ) ? 1 : 0;
    end

`ifdef ENABLE_BIOS
    //bios
    reg bios_req;
    wire [7:0] bios_dout;
    always @ (posedge clk_54m) begin
        bios_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1 && exp_slot0_num[0] == 1) ? 1 : 0;
    end

`ifdef DIAG_AUTOBOOT
    //--- embedded diagnostic cartridge: slot 0-3 (pri 0, sub 3), page 1.
    //--- BIOS slot-scan finds its 'AB' header and auto-boots it (no SD).
    reg        diag_req;
    wire [7:0] diag_dout;
    always @ (posedge clk_54m) begin
        diag_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1 && exp_slot0_num[3] == 1 && page_num[1] == 1 ) ? 1 : 0;
    end
    diag_rom diagrom1 ( .clk(clk_54m), .addr(bus_addr[13:0]), .dout(diag_dout) );
`endif

    //subrom
    reg subrom_req;
    wire [7:0] subrom_dout;
    always @ (posedge clk_54m) begin
        subrom_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 && page_num[0] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //msx logo
    reg msx_logo_req;
    wire [7:0] msx_logo_dout;
    always @ (posedge clk_54m) begin
        msx_logo_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //subrom + logo
    reg subrom_logo_req;
    always @ (posedge clk_54m) begin
        subrom_logo_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && (page_num[0] == 1 || page_num[1] == 1) && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //kanji driver
`ifndef DIAG_SLIM
    reg kanji_driver_req;
    always @ (posedge clk_54m) begin
        kanji_driver_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && (page_num[1] == 1 || page_num[2] == 1) && pri_slot_num[0] == 1 && exp_slot0_num[1] == 1 ) ? 1 : 0;
    end
`else
    wire kanji_driver_req = 1'b0;
`endif


`else

    wire bios_req;
    wire [7:0] bios_dout;
    wire subrom_req;
    wire [7:0] subrom_dout;
    wire msx_logo_req;
    wire [7:0] msx_logo_dout;
    wire kanji_driver_req;
    wire subrom_logo_req;

`endif

`ifndef ENABLE_WIFI
    assign uart_tx = 1'b1;
`endif
`ifdef ENABLE_WIFI

    //wifi driver
    reg wifi_req;
    always @ (posedge clk_54m) begin
        wifi_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[0] == 1 && exp_slot0_num[2] == 1 ) ? 1 : 0;
    end

    //uart
    wire uart_req;
    wire wait_uart;
    wire [7:0] uart_dout;

    assign uart_req = (bus_addr[7:1] == 7'b0000011 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // ESP ports 06-07h

    wifi uwifi (
        .clk_i      (clk_27m),
        .wait_o     (wait_uart),
        .reset_i    (bus_reset_n),
        .iorq_i     (bus_iorq_n),
        .wrt_i      (bus_wr_n),
        .rd_i       (bus_rd_n),
        .rx_i       (uart_rx),
        .tx_o       (uart_tx),
        .adr_i      (bus_addr),
        .db_i       (cpu_dout),
        .db_o       (uart_dout)
    );

`endif

    //----------------------------------------------------------------
    //-- USB keyboard virtual-matrix UART receiver (RP2040 -> pin 75)
    //--   Runs entirely in clk_54m (same domain as the cpu_din mux and the
    //--   vkey_col latch), so there is no multi-bit CDC; only the raw RX pin
    //--   is async and is 2-flop synchronized inside the module. Drives
    //--   vkey_row, which is merged with the physical keyboard read in the
    //--   cpu_din mux. v1: cmd_* pulse outputs are left open (Gowin trims).
    //----------------------------------------------------------------
`ifndef DIAG_SLIM
    kbd_uart_rx #(.CLK_FREQ(54_000_000), .BAUD(115200)) ukbd (
        .clk                 (clk_54m),
        .reset_n             (bus_reset_n),
        .rx                  (kbd_uart_rx_pin),
        .vkey_col            (vkey_col),
        .vkey_row_out        (vkey_row),
        .joy_state0          (joy_usb0),
        .joy_state1          (joy_usb1),
        .fw_version          (kbd_fw_version),
        .cmd_scanline_toggle (),
        .cmd_reset_pulse     (),
        .cmd_osd_toggle      ()
    );
`else
    assign vkey_row = 8'hFF;        // no USB keyboard: A9 is the board's alone
    assign joy_usb0 = 8'h00;
    assign joy_usb1 = 8'h00;
`endif

    //rtc
    wire rtc_req_r;
    wire rtc_req_w;
    wire [7:0] rtc_dout;
    assign rtc_req_w = (bus_addr[7:1] == 7'b1011010 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1 : 0; // I/O:B4-B5h   / RTC
    assign rtc_req_r = (bus_addr[7:1] == 7'b1011010 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // I/O:B4-B5h   / RTC

    rtc rtc1(
        .clk21m(clk_27m),
        .reset(0),
        .clkena(clk_enable_3m6_27),
        .req(rtc_req_w | rtc_req_r),
        .ack(),
        .wrt(rtc_req_w),
        .adr(bus_addr),
        .dbi(rtc_dout),
        .dbo(cpu_dout)
    );

    //vdp
	wire vdp_csw_n; //VDP write request
	wire vdp_csr_n; //VDP read request	
    wire [7:0] vdp_dout;
    wire vdp_int;
    wire WeVdp_n;
    wire [16:0] VdpAdr;
    wire [15:0] VrmDbi;
    wire [7:0] VrmDbo;
    wire VideoDHClk;
    wire VideoDLClk;
    assign vdp_csw_n = (bus_addr[7:2] == 6'b100110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 0:1; // I/O:98-9Bh   / VDP (V9938/V9958)
    assign vdp_csr_n = (bus_addr[7:2] == 6'b100110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 0:1; // I/O:98-9Bh   / VDP (V9938/V9958)

    v9958_top vdp4 (
        .clk (clk_27m),
        .s1 (0),
        .clk_50 (0),
        .clk_125 (0),

    `ifdef ENABLE_V9958
        .reset_n (bus_reset_n ),
    `else
        .reset_n (0),
    `endif
        .mode    (bus_addr[1:0]),
        .csw_n   (vdp_csw_n | diag_vdp_ext),      // Doctor: deselected while
        .csr_n   (vdp_csr_n | diag_vdp_ext),      // the board's VDP is under test

        .int_n   (vdp_int),
        .gromclk (),
        .cpuclk  (),
        .cdi     (vdp_dout),
        .cdo     (cpu_dout),

        .audio_sample   (audio_sample),

        .adc_clk  (),
        .adc_cs   (),
        .adc_mosi (),
        .adc_miso (0),

        .maxspr_n    (1),
    `ifdef ENABLE_SCAN_LINES
        .scanlin_n   (~config_enable_scanlines),
    `else
        .scanlin_n   (1),
    `endif
        .gromclk_ena_n (1),
        .cpuclk_ena_n  (1),

        .WeVdp_n(WeVdp_n),
        .VdpAdr(VdpAdr),
        .VrmDbi(VrmDbi2),
        .VrmDbo(VrmDbo),

        .VideoDHClk(VideoDHClk),
        .VideoDLClk(VideoDLClk),

        .version_mismatch(version_mismatch),

        .tmds_clk_p    (clk_p),
        .tmds_clk_n    (clk_n),
        .tmds_data_p   (data_p),
        .tmds_data_n   (data_n)
    );

`ifdef ENABLE_MAPPER
    //mapper
    wire mapper_read;
    wire mapper_write;
    wire mapper_req;
    reg mapper_req3;
    reg mapper_req12;
    reg [7:0] mapper_dout;
    wire [21:0] mapper_addr;
    reg [7:0] mapper_reg0;
    reg [7:0] mapper_reg1;
    reg [7:0] mapper_reg2;
    reg [7:0] mapper_reg3;
    wire mapper_reg_write;

    assign mapper_addr = (bus_addr [15:14] == 2'b00 ) ? { mapper_reg0, bus_addr[13:0] } :
                         (bus_addr [15:14] == 2'b01 ) ? { mapper_reg1, bus_addr[13:0] } :
                         (bus_addr [15:14] == 2'b10 ) ? { mapper_reg2, bus_addr[13:0] } :
                                                        { mapper_reg3, bus_addr[13:0] };

    always @ (posedge clk_54m) begin
`ifdef DIAG_AUTOBOOT
        // Doctor: while physical slot 3 is transparent the internal mapper
        // must not take the cycle either - a page-2 fill with port FE = 0
        // would land in segment 0, i.e. our own page 3 - except page 3
        // itself (stack/variables) unless p3_release hands it to the board
        mapper_req3 <= ( bus_rfsh_n == 1 && config_enable_mapper3 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[0] == 1 && xffff == 0
                         && !(diag_slot3_ext == 1 && !(page_num[3] == 1 && diag_p3_release == 0)) ) ? 1 : 0;
`else
        mapper_req3 <= ( bus_rfsh_n == 1 && config_enable_mapper3 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[0] == 1 && xffff == 0) ? 1 : 0;
`endif
        mapper_req12 <= ( config_enable_mapper12 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_mapper_slot ) ? 1 : 0;
    end
    assign mapper_req = mapper_req3 | mapper_req12;
    assign mapper_read = mapper_req & ~bus_rd_n;
    assign mapper_write = mapper_req & ~bus_wr_n;
    assign mapper_reg_write = ( (bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0) && (bus_addr [7:2] == 6'b111111) )?1:0;

    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
            mapper_reg0	<= 8'b00000011;
            mapper_reg1	<= 8'b00000010;
            mapper_reg2	<= 8'b00000001;
            mapper_reg3	<= 8'b00000000;
        end
        else if (mapper_reg_write == 1) begin
            case (bus_addr[1:0])
                2'b00: mapper_reg0 <= cpu_dout[7:0];
                2'b01: mapper_reg1 <= cpu_dout[7:0];
                2'b10: mapper_reg2 <= cpu_dout[7:0];
                2'b11: mapper_reg3 <= cpu_dout[7:0];
            endcase
        end
    end
`else
    wire mapper_read;
    wire mapper_write;
    wire mapper_req;
    reg [7:0] mapper_dout;
    wire [21:0] mapper_addr;
    assign mapper_read = 0;
    assign mapper_write = 0;
    assign mapper_addr = 22'd0;
`endif

    reg [15:0] VrmDbi2;
    reg [7:0] megaram_dout;
    wire [22:0] ram_addr;
    wire ram_read;
    wire ram_write;
    wire ram_req;
    wire [7:0] ram_din;
    reg [7:0] ram_dout;
    reg ram_busy;

    //rom map, 512 KB, [18:0]
    //876 54321098 76543210
    //111 11xxxxxx xxxxxxxx free, 16 KB, 0x7c000 - 0x7ffff
    //111 10xxxxxx xxxxxxxx esp8266, 16 KB, 0x78000 - 0x7bfff
    //111 0xxxxxxx xxxxxxxx kanji, 32 KB, 0x70000 - 0x77fff
    //110 11xxxxxx xxxxxxxx fm + logo + boot menu, 16 KB, 0x6c000 - 0x6ffff
    //110 10xxxxxx xxxxxxxx msx2+ subrom, 16 KB, 0x68000 - 0x6bfff
    //110 0xxxxxxx xxxxxxxx msx2+ bios, 32 KB, 0x60000 - 0x67fff
    //10x xxxxxxxx xxxxxxxx wondertang disk, 128 KB, 0x40000 - 0x5ffff
    //01x xxxxxxxx xxxxxxxx jis2, 128 KB, 0x20000 - 0x3ffff
    //00x xxxxxxxx xxxxxxxx jis1, 128 KB, 0x00000 - 0x1ffff

    //sdram map, 8 MB, [22:0]
    //2109876 54321098 76543210
    //11111xx xxxxxxxx xxxxxxxx vram, 256 KB, bank D
    //1110111 10xxxxxx xxxxxxxx esp8266, 16 KB, 0x778000 - 0x77bfff
    //1110111 0xxxxxxx xxxxxxxx kanji driver, 32 KB, 0x770000 - 0x777fff
    //1110110 11xxxxxx xxxxxxxx fm + logo + boot menu, 16 KB, 0x76c000 - 0x76ffff
    //1110110 10xxxxxx xxxxxxxx msx2+ subrom, 16 KB, 0x768000 - 0x76bfff
    //1110110 0xxxxxxx xxxxxxxx msx2+ bios, 32 KB, 0x760000 - 0x767fff
    //111010x xxxxxxxx xxxxxxxx wondertang disk, 128 KB, bank D, 0x740000 - 0x75ffff
    //11100xx xxxxxxxx xxxxxxxx kanji data jis1 + jis2, 256 KB, 0x700000 - 0x73ffff
    //10xxxxx xxxxxxxx xxxxxxxx megaram, 2 MB, bank C
    //0xxxxxx xxxxxxxx xxxxxxxx mapper, 4 MB, banks A+B

    assign ram_addr = (~flash_idle) ? rom_addr :
                `ifdef ENABLE_MAPPER
                        (mapper_req == 1) ? { 1'b0, mapper_addr[21:0] } :  //bank A+B
                `endif
                        (bios_req == 1 ) ? { 8'b11101100, bus_addr[14:0] } : //bank D
                        (subrom_logo_req == 1 ) ? { 8'b11101101, bus_addr[14:0] } : //bank D
                `ifdef ENABLE_SDCARD
                        (megarom_req == 1 ) ? { 6'b111010, megarom_addr[16:0] } : //bank D
                `endif
                        (megaram_req == 1 ) ? { 2'b10, megaram_addr[20:0] } :  //bank C
                        (kanji_driver_req == 1 ) ? { 8'b11101110, ~bus_addr[14], bus_addr[13:0] } : //bank D
                        (kanji_data_ram_req == 1 ) ? { 5'b11100, kanji_data_ram_addr[17:0] } : //bank D
                `ifdef ENABLE_WIFI
                        (wifi_req == 1 ) ? { 9'b111011110, bus_addr[13:0] } : //bank D
                `endif
                        23'h7fffff; 
    
    assign ram_read = (~flash_idle) ? 0 : 
                `ifdef ENABLE_MAPPER
                      (mapper_read == 1) ? ~bus_rd_n :
                `endif
                      (bios_req == 1) ? ~bus_rd_n :
                      (subrom_logo_req == 1) ? ~bus_rd_n :
                `ifdef ENABLE_SDCARD
                      (megarom_req == 1) ? ~bus_rd_n :
                `endif
                      (megaram_req == 1) ? ~bus_rd_n :
                      (kanji_driver_req == 1) ? ~bus_rd_n :
                      (kanji_data_ram_req == 1) ? ~bus_rd_n :
                `ifdef ENABLE_WIFI
                      (wifi_req == 1) ? ~bus_rd_n :
                `endif
                      0;
    
    assign ram_write = (~flash_idle) ? rom_write : 
                `ifdef ENABLE_MAPPER
                      (mapper_write == 1 ) ? ~bus_wr_n :
                `endif
                      (megaram_wrt == 1) ? ~bus_wr_n :
                      0; 

    assign ram_req = (~flash_idle) ? rom_write : 
                     (mapper_req == 1) ? mapper_req:
                     (bios_req == 1) ? bios_req:
                     (subrom_logo_req == 1) ? subrom_logo_req:
                `ifdef ENABLE_SDCARD
                     (megarom_req == 1) ? megarom_req:
                `endif
                     (megaram_req == 1) ? megaram_req:
                     (kanji_driver_req == 1) ? kanji_driver_req:
                     (kanji_data_ram_req == 1) ? kanji_data_ram_req:
                `ifdef ENABLE_WIFI
                     (wifi_req == 1) ? wifi_req:
                `endif
                      0;

    assign ram_din = (~flash_idle) ? { rom_dout, rom_dout }  : { cpu_dout, cpu_dout };

memory_ctrl mem1 (
    .clk_27m(clk_54m),
    .clk_108m(clk_108m),
    .bus_reset_n(bus_reset_n ),
    .video_dhclk(VideoDHClk),
    .video_dlclk(VideoDLClk),

    .ram_din(ram_din),
    .ram_req(ram_req),
    .ram_write(ram_write),
    .ram_addr(ram_addr),
    .vram_din(VrmDbo),
    .vram_write(~WeVdp_n),
    .vram_addr(VdpAdr),
    .bus_rfsh_n(bus_rfsh_n),

    .ram_dout(ram_dout),
    .vram_dout(VrmDbi2),
    .ram_busy(ram_busy),

    .O_sdram_clk(O_sdram_clk),
    .O_sdram_cke(O_sdram_cke),
    .O_sdram_cs_n(O_sdram_cs_n),
    .O_sdram_cas_n(O_sdram_cas_n),
    .O_sdram_ras_n(O_sdram_ras_n),
    .O_sdram_wen_n(O_sdram_wen_n),
    .IO_sdram_dq(IO_sdram_dq),
    .O_sdram_addr(O_sdram_addr),
    .O_sdram_ba(O_sdram_ba),
    .O_sdram_dqm(O_sdram_dqm)
);




`ifdef ENABLE_SOUND

    //YM219 PSG
    wire psgBdir;
    wire psgBc1;
    wire iorq_wr_n;
    wire iorq_rd_n;
    wire [7:0] psg_dout;
    wire [7:0] psgSound1;
    wire [7:0] psgPA;
    wire [7:0] psgPB;
    reg clk_1m8;
    assign iorq_wr_n = bus_iorq_n | bus_wr_n;
    assign iorq_rd_n = bus_iorq_n | bus_rd_n;
    assign psgBdir = ( bus_addr[7:3]== 5'b10100 && iorq_wr_n == 0 && bus_addr[1]== 0 ) ?  1 : 0; // I/O:A0-A2h / PSG(AY-3-8910) bdir = 1 when writing to &HA0-&Ha1
    assign psgBc1 = ( bus_addr[7:3]== 5'b10100 && ((iorq_rd_n==0 && bus_addr[1]== 1) || (bus_addr[1]==0 && iorq_wr_n==0 && bus_addr[0]==0))) ? 1 : 0; // I/O:A0-A2h / PSG(AY-3-8910) bc1 = 1 when writing A0 or reading A2
    assign psgPA =8'h00;
    reg psgPB = 8'hff;

    wire clk_enable_1m8;
    reg clk_1m8_prev;
    always @ (posedge clk_27m) begin
        if (clk_enable_3m6_27) begin
            clk_1m8 <= ~clk_1m8;
        end
    end
    assign clk_enable_1m8 = (clk_enable_3m6_27 == 1 && clk_1m8 == 1);

    YM2149 psg1 (
        .I_DA(cpu_dout),
        .O_DA(),
        .O_DA_OE_L(),
        .I_A9_L(0),
        .I_A8(1),
        .I_BDIR(psgBdir),
        .I_BC2(1),
        .I_BC1(psgBc1),
        .I_SEL_L(1),
        .O_AUDIO(psgSound1),
        .I_IOA(psgPA),
        .O_IOA(),
        .O_IOA_OE_L(),
        .I_IOB(psgPB),
        .O_IOB(psgPB),
        .O_IOB_OE_L(),
        
        .ENA(clk_enable_1m8), // clock enable for higher speed operation
        .RESET_L(bus_reset_n),
        .CLK(clk_27m),
        .clkHigh(clk_27m),
        .debug ()
    );

    wire [7:0] psgSound3;
    psg_filter filter1 (
        .clk_27m (clk_27m),
        .reset (~bus_reset_n),
        .data_in (psgSound1),
        .data_out (psgSound3)
    );

    //opll
    wire opll_req_n; 
    wire [9:0] opll_mo;
    wire [9:0] opll_ro;
    reg [11:0] opll_mix;
    wire [15:0] jt2413_wav;

    assign opll_req_n = ( bus_iorq_n == 1'b0 && bus_addr[7:1] == 7'b0111110  &&  bus_wr_n == 1'b0 )  ? 1'b0 : 1'b1;    // I/O:7C-7Dh   / OPLL (YM2413)
  
    jt2413 opll(
        .rst (~bus_reset_n),        // rst should be at least 6 clk&cen cycles long
        .clk (clk_27m),        // CPU clock
        .cen (clk_enable_3m6_27),        // optional clock enable, if not needed leave as 1'b1
        .din (cpu_dout),
        .addr (bus_addr[0]),
        .cs_n (opll_req_n),
        .wr_n (1'b0),
        // combined output
        .snd (jt2413_wav),
        .sample   ( )
    ); 

    //scc & ghost scc
    wire [14:0] scc_wav;
    wire [7:0] scc_dout;
    wire scc_req;
    reg scc_req3;
    wire scc_req3_r;
    reg scc_req12;

    wire scc_wrt;
    
    reg x98h;
    always @ (posedge clk_27m) begin
        x98h <= ( bus_addr[15:8] == 8'h98 ) ? 1 : 0;
    end

    reg [7:0] scc_bank2;
    reg scc_enable_req3;
    reg scc_enable_req12;
    wire scc_enable_req;
    always @ (posedge clk_27m) begin
        scc_enable_req3 <= ( bus_addr[15:11] == 5'b10010 && bus_mreq_n == 0 && bus_wr_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[3] == 1 ) ? 1 : 0;
        scc_enable_req12 <= ( config_enable_megaram12 == 1 && bus_addr[15:11] == 5'b10010 && bus_mreq_n == 0 && bus_wr_n == 0 && pri_slot == config_megaram_slot ) ? 1 : 0;
    end
    assign scc_enable_req = scc_enable_req3 | scc_enable_req12;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            scc_bank2 <= 8'h00;
        else begin
            if (scc_enable_req == 1 ) begin
                scc_bank2 <= cpu_dout;
            end
        end
    end

    wire scc_enable;
    assign scc_enable = ( scc_bank2 == 8'h3f ) ? 1 : 0;

    always @ (posedge clk_27m) begin
        scc_req3 <= ( config_enable_megaram3 == 1 && scc_enable == 1 && x98h == 1 && bus_mreq_n == 0 && (bus_wr_n == 0 || bus_rd_n == 0 ) && pri_slot == config_megaram_slot && exp_slotx_num[3] == 1  ) ? 1 : 0;
        scc_req12 <= ( config_enable_megaram12 == 1 && scc_sound_disable == 0 && scc_enable == 1 && x98h == 1 && bus_mreq_n == 0 && (bus_wr_n == 0 || bus_rd_n == 0 ) && pri_slot == config_megaram_slot ) ? 1 : 0;
    end
    assign scc_req = scc_req3 | scc_req12;
    assign scc_req3_r = ( scc_req3 == 1 && bus_rd_n == 0 ) ? 1 : 0;
    assign scc_wrt = ( scc_req == 1 && bus_wr_n == 0 ) ? 1 : 0;

    scc_wave2 SccCh (
        .clk21m (clk_27m),
        .reset (~bus_reset_n),
        .clkena (clk_enable_3m6_27),
        .req ( scc_req),
        .ack (),
        .wrt (scc_wrt),
        .adr (bus_addr[7:0]),
        .dbi (scc_dout),
        .dbo (cpu_dout),
        .wave (scc_wav)
    );

    reg scc2_req3;
    reg scc2_req12;
    wire scc2_req;
    wire scc2_req_r;
    wire scc2_wrt;
    wire [7:0] scc2_dout;
    wire [14:0] scc2_wav;
    wire megaram_req;
    wire megaram_wrt;
    wire [20:0] megaram_addr;
    wire megaram_enabled;

    always @ (posedge clk_54m) begin
        scc2_req3 <= ( config_enable_ghost_scc == 0 && config_enable_megaram3 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_megaram_slot && exp_slotx_num[3] == 1  && xffff == 0) ? 1 : 0;
        scc2_req12 <= ( config_enable_ghost_scc == 0 && config_enable_megaram12 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_megaram_slot ) ? 1 : 0;
        //scc2_req <= ( bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot_num[2] == 1 ) ? 1 : 0;
    end
    assign scc2_req = scc2_req3 | scc2_req12;
    assign scc2_req_r = ( scc2_req == 1 && bus_rd_n == 0 ) ? 1 : 0;
    assign scc2_wrt = ( scc2_req == 1 && bus_wr_n == 0 ) ? 1 : 0;

    wire [1:0] map_sel;
    wire map_linear;
    wire scc_sound_disable;
    assign map_sel = Slot2Mode;
    assign map_linear = iSlt2_linear;

    megaram_scc megaram1 (
        .clk_27m (clk_54m),
        .bus_reset_n (bus_reset_n),
        .bus_addr (bus_addr),
        .cpu_dout (cpu_dout),
        .bus_rd_n (bus_rd_n),
        .bus_wr_n (bus_wr_n),
        .scc_req (scc2_req),
        .scc_wrt (scc2_wrt),
        .map_sel (map_sel),
        .map_linear (map_linear),

        .megaram_req (megaram_req),
        .megaram_wrt (megaram_wrt), 
        .megaram_addr (megaram_addr),
        .scc_sound_disable (scc_sound_disable)
    );


    //mixer
    reg [23:0] fm_wav;
    reg [16:0] fm_mix;
    reg [14:0] scc_wav2;
	reg [15:0] audio_sample;

    always @ (posedge clk_27m) begin
        if (clk_enable_3m6_27 == 1 ) begin
            if (map_sel[0] == 0)
                audio_sample <= { 2'b0 , psgSound3 , 6'b000000 } + { scc_wav, 1'b0 } + jt2413_wav;
            else
                audio_sample <= { 2'b0 , psgSound3 , 6'b000000 } + jt2413_wav;
        end
    end

`else

    wire scc2_req;
    wire [14:0] scc2_wav;
    wire megaram_req;
    wire [20:0] megaram_addr;
    wire megaram_enabled;
    wire [15:0] audio_sample;
    wire megaram_wrt;

`endif

    //kanji data
    wire kanji_data_req_r;
    wire kanji_data_req_w;
    wire kanji_data_ram_req;
    reg [7:0] kanji_data_dout;
    wire [17:0] kanji_data_ram_addr;
`ifdef DIAG_SLIM
    // Doctor: no kanji data ports - their I/O decode reaches the SDRAM
    // controller inside the IORQ_n half cycle and was the last path that
    // would not close; a kanji ROM on the board still answers via the bus
    assign kanji_data_req_w = 1'b0;
    assign kanji_data_req_r = 1'b0;
`else
    assign kanji_data_req_w = (bus_addr[7:2] == 6'b110110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1 : 0; // I/O:B4-B5h   / I/O:D8-DBh / Kanji-data
    assign kanji_data_req_r = (bus_addr[7:2] == 6'b110110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // I/O:B4-B5h   / I/O:D8-DBh / Kanji-data
`endif

    kanji kanji1(
        .clk21m(clk_27m),
        .reset(0),
        .req(kanji_data_req_w | kanji_data_req_r),
        .wrt(kanji_data_req_w),
        .adr(bus_addr),
        .dbo(cpu_dout),
        .ramreq(kanji_data_ram_req),
        .ramadr(kanji_data_ram_addr)
    );

`ifdef ENABLE_WIFI
    //f2 port
    wire f2_req_r;
    wire f2_req_w;
    reg [7:0] f2_port;

    assign f2_req_r = (bus_addr[7:0] == 8'hf2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign f2_req_w = (bus_addr[7:0] == 8'hf2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            f2_port <= 8'h00;
        else begin
            if (f2_req_w == 1 ) begin
                f2_port <= cpu_dout;
            end
        end
    end
`endif

    localparam CONFIG1_DEFAULT = 8'hfb;
    localparam CONFIG2_DEFAULT = 8'h0f;

`ifdef ENABLE_CONFIG
    //config
    reg [7:0] config0_ff = 8'h00;
    reg [7:0] config1_ff = CONFIG1_DEFAULT;
    reg [7:0] config1_temp_ff;
    reg [7:0] config2_ff = CONFIG2_DEFAULT;
    reg [7:0] config2_temp_ff;
    reg [1:0] config_mapper_slot_ff = 2'b11;
    reg [1:0] config_megaram_slot_ff = 2'b11;
    reg [1:0] config_sdcard_slot_ff = 2'b11;
    reg config_enable_mapper3;
    reg config_enable_mapper12;
    wire config_enable_megaram;
    wire config_enable_megaram3;
    wire config_enable_megaram12;
    wire config_enable_ghost_scc;
    reg config_enable_sdcard;
    wire config_enable_wait;
    reg config_reset_ff;
    reg config_flash_write_ff;
    reg config_update;
    wire config_enable_scanlines;
    wire [1:0] config_mapper_slot;
    wire [1:0] config_megaram_slot;
    wire [1:0] config_sdcard_slot;
    wire [1:0] config_keyboard;
    wire config0_req;
    wire config1_req;
    wire config2_req;
    wire config_reset_req;
    wire config_reset;
    wire config_ok;
    wire [7:0] config_dout;
    wire config_req;

    always @ (posedge clk_27m) begin
        config_reset_ff <= 0;
        config_flash_write_ff <= 0;
        config_update <= 0;
        if (clk_enable_3m6_27 == 1 ) begin
            if (config0_req == 1 ) begin
                config0_ff <= ~cpu_dout;
            end

            if (config1_req == 1 ) begin
                config_update <= 1;
                config1_temp_ff <= cpu_dout;
            end
            if (config2_req == 1 ) begin
                config_update <= 1;
                config2_temp_ff <= cpu_dout[5:0];
                if ( cpu_dout[6] == 1) begin
                    config_flash_write_ff <= 1;
                end
                if ( cpu_dout[7] == 1) begin
                    config_reset_ff <= 1;
                end
            end
        end
    end

    reg [2:0] ocm_slot2_prev; //bit2 = linear ,bits 1,0 = mode
    reg ocm_update;
    always @ (posedge clk_27m) begin
        ocm_update <= 0;
        if ( { iSlt2_linear, Slot2Mode } != ocm_slot2_prev ) begin
            ocm_update <= 1;
        end
    end

    reg config_init_delay = 0;
    always @ (posedge clk_27m) begin
        config_init_delay <= config_init;
        if (config_init == 1 ) begin
            if (s2 == 1) begin
                config1_ff <= CONFIG1_DEFAULT;
                config2_ff <= CONFIG2_DEFAULT;
            end
            else begin
                config1_ff <= config_sig[2];
                config2_ff <= config_sig[3];
            end
        end
        if (config_update == 1) begin
            config1_ff <= config1_temp_ff;
            config2_ff <= config2_temp_ff;
        end
        if (ocm_update == 1) begin
            config1_ff[7:6] <= 2'b10;
            config1_ff[1] <= 1;
            ocm_slot2_prev <= { iSlt2_linear, Slot2Mode };
        end
    end

    monostable mono (
        .pulse_in(config_reset_ff),
        .clock(clk_27m),
        .pulse_out(config_reset_req)
    );
    assign config_reset = (config_reset_req == 1 && flash_write_busy == 0) ? 1 : 0;

    assign config_ok = (config0_ff == 8'hb7) ? 1 : 0;
    assign config0_req = (bus_addr[7:0] == 8'h40 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config1_req = (config_ok == 1 && bus_addr[7:0] == 8'h41 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config2_req = (config_ok == 1 && bus_addr[7:0] == 8'h42 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config_enable_scanlines = config1_ff[3];
    //assign config_keyboard = config2_ff[4:3];
    assign config_enable_wait = config2_ff[3];
    assign config_req = (bus_addr[7:4] == 4'h4 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign config_dout = ( bus_addr[3:0] == 4'h0 ) ? config0_ff :
                         ( bus_addr[3:0] == 4'h1 ) ? config1_ff :
                         ( bus_addr[3:0] == 4'h2 ) ? config2_ff : 8'hff;


    always @ (posedge clk_54m) begin
        if (bus_reset_n == 0 || config_init_delay == 1 ) begin
            config_mapper_slot_ff <= config1_ff[5:4];
            config_enable_mapper3 <= (config1_ff[0] == 1 && config1_ff[5:4] == 2'b11);
            config_enable_mapper12 <= (config1_ff[0] == 1 && config1_ff[5:4] != 2'b11);
            //config_megaram_slot_ff <= config1_ff[7:6];
            config_enable_sdcard <= config2_ff[0];
            config_sdcard_slot_ff <= config2_ff[2:1];
        end
    end
    assign config_mapper_slot = config_mapper_slot_ff;
    assign config_megaram_slot = config1_ff[7:6];;
    assign config_sdcard_slot = config_sdcard_slot_ff;
    assign config_enable_megaram = config1_ff[1];
    assign config_enable_megaram3 = (config1_ff[1] == 1 && config1_ff[7:6] == 2'b11);
    assign config_enable_megaram12 = (config1_ff[1] == 1 && config1_ff[7:6] != 2'b11 );
    assign config_enable_ghost_scc = config1_ff[2];

`else

    wire config_enable_mapper3;
    wire config_enable_mapper12;
    wire config_enable_megaram;
    wire config_enable_megaram3;
    wire config_enable_megaram12;
    wire config_enable_ghost_scc;
    wire config_enable_sdcard;
    wire config_enable_scanlines;
    wire [1:0] config_mapper_slot;
    wire [1:0] config_megaram_slot;
    wire [1:0] config_sdcard_slot;
    wire config_reset;
    wire config_enable_wait;
    assign config_enable_mapper3 = 1;
    assign config_enable_mapper12 = 0;
    assign config_enable_megaram = 1;
    assign config_enable_megaram3 = 1;
    assign config_enable_megaram12 = 0;
    assign config_enable_ghost_scc = 0;
    assign config_enable_sdcard = 0;
    assign config_enable_scanlines = 0;     // Doctor: plain text is easier to read/capture
    assign config_mapper_slot = 2'b11;
    assign config_megaram_slot = 2'b11;
    assign config_sdcard_slot= 2'b11;
    assign config_reset = 0;
    assign config_enable_wait = 1;          // = CONFIG2_DEFAULT bit3
    wire config_flash_write_ff = 1'b0;      // no settings writer

`endif

    /// FLASH ROM LOADER - BIOS
    localparam FLASH_START_ADDRESS = 24'h200000;
    localparam RAM_START_ADDRESS = 23'h6fffff;
    localparam GOAULD_ROM_SIZE = 512*1024 + 6; //512KB + signature (AB) + config
    reg ff_rom_wr = 0;
    reg [24:0] ff_rom_addr;
    
    wire rom_write;
    wire [7:0] rom_dout;
    wire [24:0] rom_addr;
    assign rom_write = flash_busy;
    assign rom_dout = ff_rom_dout;
    assign rom_addr = ff_rom_addr;
    
    reg [31:0] ff_flash_counter;

//flash
    reg [23:0] ff_flash_addr = 24'd0;

    // Version guard: the pack's version byte is the LAST byte of the 512KB BIOS
    // pack (flash 0x200000 + 0x7FFFF). The loader streams the whole pack at
    // boot, so we just latch that byte as it goes by. 0x00 until read; 0xFF on
    // packs that predate the version guard.
    localparam [23:0] PACK_VER_FLASH_ADDR = 24'h27FFFF;
    reg [7:0] ff_pack_version = 8'h00;
    reg ff_flash_rd = 0;
    reg ff_flash_terminate = 0;
    reg [7:0] ff_rom_dout;
    reg flash_wait_n;
    wire[7:0] flash_dout;
    wire flash_data_ready;
    wire flash_busy;
    wire [7:0] flash_write_din;
    wire flash_write_busy;
    wire [7:0] flash_write_counter;
    wire flash_write_terminate;
    assign flash_write_din = (flash_write_counter == 8'd00) ? 8'h41 :
                             (flash_write_counter == 8'd01) ? 8'h42 :
                        `ifdef ENABLE_CONFIG
                             (flash_write_counter == 8'd02) ? config1_ff :
                             (flash_write_counter == 8'd03) ? config2_ff : 8'hff;
                        `else
                             (flash_write_counter == 8'd02) ? CONFIG1_DEFAULT :
                             (flash_write_counter == 8'd03) ? CONFIG2_DEFAULT : 8'hff;
                        `endif
    assign flash_write_terminate = (flash_write_counter == 8'd6) ? 1 : 0;

    flash # (
        .STARTUP_WAIT(1)
    )
    flash1
    (
        .clk(clk_54m),
        .reset_n(bus_reset_n),
        .SCLK(mspi_sclk),
        .CS(mspi_cs),
        .MISO(mspi_miso),
        .MOSI(mspi_mosi),
        .addr(ff_flash_addr),
        .rd(ff_flash_rd),
        .dout(flash_dout),
        .data_ready(flash_data_ready),
        .busy(flash_busy),
        .terminate(ff_flash_terminate),
        .write_enable(config_flash_write_ff),
        .write_din(flash_write_din),
        .write_busy(flash_write_busy),
        .write_counter(flash_write_counter),
        .write_terminate(flash_write_terminate),
        .write_addr(24'h280000) //24'h278000)
    );

    reg [7:0] ff_flash_state = 8'd0;
    
    localparam STATE_RESET          = 8'd0;
    localparam STATE_READ_START     = 8'd1;
    localparam STATE_READ_LOOP      = 8'd2;
    localparam STATE_IDLE           = 8'd3;
    localparam STATE_INIT1          = 8'd4;
    localparam STATE_INIT2          = 8'd5;
    localparam STATE_INIT3          = 8'd6;
    localparam STATE_INIT4          = 8'd7;
    reg [31:0] nose = 0;
    wire flash_idle;
    assign flash_idle = (ff_flash_state == STATE_IDLE ) ? 1'b1 : 1'b0;
    
    always @(posedge clk_54m, negedge reset3_n) begin
    if (reset3_n == 0) begin
        ff_flash_state = STATE_RESET;
        ff_flash_rd <= 0;
        ff_rom_wr <= 0;
        nose <= 0;
    end else
        case (ff_flash_state)
    
            STATE_RESET: begin   // reset
                ff_flash_state <= STATE_READ_START;
                ff_flash_rd <= 0;
                ff_rom_wr <= 0;
                ff_flash_terminate <= 0;
            end
    
            STATE_INIT1: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= 24'h000000;
                    ff_flash_rd <= 1;
                    ff_flash_state = STATE_INIT2;
                end
            end
    
            STATE_INIT2: begin  // start read
                if (flash_busy == 1) begin
                    ff_flash_rd <= 0;
                    ff_flash_state = STATE_INIT3;
                end
            end
            
            STATE_INIT3: begin  // start read
                if (flash_busy == 0) begin
                    nose <= 0;
                    ff_flash_terminate <= 1;
                    ff_flash_state = STATE_INIT4;
                end
            end
    
            STATE_INIT4: begin  // start read
                nose <= nose + 1;
                if (nose > 10) begin
                    ff_flash_terminate <= 0;
                    ff_flash_state = STATE_READ_START;
                end
            end
    
            STATE_READ_START: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= FLASH_START_ADDRESS;
                    ff_rom_addr <= RAM_START_ADDRESS;
                    ff_flash_rd <= 1;
                    ff_flash_state = STATE_READ_LOOP;
                    ff_flash_counter <= GOAULD_ROM_SIZE;
                end
            end
    
            STATE_READ_LOOP: begin  // loop read
                if (flash_busy == 0) begin
    
                    if (ff_flash_counter > 0) begin
                        
                        if (~ff_flash_rd) begin
    
                            ff_flash_addr <= ff_flash_addr + 1;
                            ff_flash_counter <= ff_flash_counter - 1;
                            ff_flash_rd <= 1;
    
                            ff_rom_wr <= 1;
                            ff_rom_addr <= ff_rom_addr + 1;
                            ff_rom_dout <= flash_dout;

                            // Version guard: capture the pack version byte as
                            // the loader streams past it (same data, same beat).
                            if (ff_flash_addr == PACK_VER_FLASH_ADDR)
                                ff_pack_version <= flash_dout;

                        end
                    end else begin    
                        ff_rom_wr <= 0;
                        ff_flash_rd <= 0;
                        ff_flash_state <= STATE_IDLE;
                    end
                end else begin
                    ff_rom_wr <= 0;
                    ff_flash_rd <= 0;
                end
            end
    
            STATE_IDLE: begin  // idle
                ff_flash_terminate <= 1;
            end
    
        endcase
    end

    // configuration + signature
    reg [7:0] config_sig [0:5];
    reg [2:0] last_bytes_cnt;
    wire new_byte;
    wire config_init;
    assign new_byte = (~ff_flash_rd && flash_busy == 0);
    assign config_init = (config_sig[0] == 8'h41 && config_sig[1] == 8'h42 && last_bytes_cnt == 3'd1) ? 1 : 0;

    always @(posedge clk_54m or negedge reset3_n) begin
        if (!reset3_n) begin
            last_bytes_cnt <= 3'd0;
            config_sig[0] <= 8'd0;
            config_sig[1] <= 8'd0;
            config_sig[2] <= 8'd0;
            config_sig[3] <= 8'd0;
            config_sig[4] <= 8'd0;
            config_sig[5] <= 8'd0;
        end else begin
            if (ff_flash_counter == 32'd6)
                last_bytes_cnt <= 3'd6;
            if (new_byte && last_bytes_cnt != 3'd0) begin
                case (last_bytes_cnt)
                    3'd6: config_sig[0] <= flash_dout;
                    3'd5: config_sig[1] <= flash_dout;
                    3'd4: config_sig[2] <= flash_dout;
                    3'd3: config_sig[3] <= flash_dout;
                    3'd2: config_sig[4] <= flash_dout;
                    3'd1: config_sig[5] <= flash_dout;
                endcase
                last_bytes_cnt <= last_bytes_cnt - 1;
            end
        end
    end


`ifdef ENABLE_SDCARD

    
   
    //megarom
    reg megarom_req;
    wire [16:0] megarom_addr;
    reg [2:0] megarom_page_ff;
    reg megarom_page_req;
    wire [2:0] megarom_page;

    always @ (posedge clk_54m) begin
        megarom_req <=     ( config_enable_sdcard == 1 && bus_mreq_n == 0 && bus_rfsh_n == 1 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && (page_num[1] == 1 || page_num[2] == 1) ) ? 1 : 0;
        megarom_page_req <= ( bus_mreq_n == 0 && bus_rfsh_n == 1 && bus_wr_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && bus_addr == 16'h6000 ) ? 1 : 0;
    end
    assign megarom_page = megarom_page_ff;
    assign megarom_addr = { megarom_page, bus_addr[13:0] };

    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
           megarom_page_ff <= 3'b0;
        end 
        else begin
            if (bus_clk_3m6_27 == 1) begin
                if (megarom_page_req == 1) begin
                    megarom_page_ff <= cpu_dout[2:0]; // select page
                end
            end
        end
    end




    /*
    reg [7:0] ff_flash_state = 8'd0;

    localparam STATE_RESET          = 8'd0;
    localparam STATE_READ_START     = 8'd1;
    localparam STATE_READ_WAIT      = 8'd2;
    localparam STATE_READ_LOOP      = 8'd3;
    localparam STATE_IDLE           = 8'd4;

    always @(posedge clk_54m, negedge bus_reset_n) begin
    if (bus_reset_n == 0) begin
        ff_flash_state = STATE_RESET;
        ff_flash_rd <= 0;
        flash_wait_n <= 1;
    end else
        case (ff_flash_state)
            STATE_RESET: begin   // reset
                ff_flash_state <= STATE_READ_START;
                ff_flash_rd <= 0;
                ff_flash_terminate <= 1;
            end
            STATE_READ_START: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= 24'h100000;
                    ff_flash_state = STATE_READ_WAIT;
                end
            end
            STATE_READ_WAIT: begin  // start read
                if (megarom_req == 1) begin
                    flash_wait_n <= 0;
                    ff_flash_addr <= megarom_addr ;
                    ff_flash_rd <= 1;
                    ff_flash_terminate <= 0;
                    ff_flash_state = STATE_READ_LOOP;
                end
            end
            STATE_READ_LOOP: begin  // loop read
                if (flash_busy == 0 && ff_flash_rd <= 0) begin
                    ff_rom_dout <= flash_dout; 
                    ff_flash_state <= STATE_IDLE;
                end
                else begin
                    ff_flash_rd <= 0;
                end
            end
            STATE_IDLE: begin  // idle
                flash_wait_n <= 1;
                ff_flash_terminate <= 1;
                if (megarom_req == 0) begin
                    ff_flash_state <= STATE_READ_START;
                end
            end
        endcase
    end*/


    //sd card
    localparam int SDC_SDATA		=  16'h7C00;		 	// rw: 7C00h-7Dff - sector transfer area
    localparam int SDC_ENABLE  	    =  16'h7E00;		    // wo: 1: enable SDC register, 0: disable
    localparam int SDC_CMD			=  SDC_ENABLE+1; 		// wo: cmd to SDC fpga: 1=sd read, 2=sd write
    localparam int SDC_STATUS		=  SDC_CMD+1;	 		// ro: SDC status bits
    localparam int SDC_SADDR		=  SDC_STATUS+1;	 	// wo: 4 bytes: sector addr for read/write
    localparam int SDC_C_SIZE  	    =  SDC_SADDR+4;			// ro: 3 bytes: device size blocks
    localparam int SDC_C_SIZE_MULT	=  SDC_C_SIZE+3;		// ro: 3 bits size multiplier
    localparam int SDC_RD_BL_LEN	=  SDC_C_SIZE_MULT+1;	// ro: 4 bits block length
    localparam int SDC_CTYPE		=  SDC_RD_BL_LEN+1;		// ro: SDC Card type: 0=unknown, 1=SDv1, 2=SDv2, 3=SDHCv2 
    localparam int SDC_MID		    =  SDC_CTYPE+1;		    // ro: manufacture ID: 8 bits unsigned
    localparam int SDC_OID		    =  SDC_MID+1;		    // ro: oem id: 2 character
    localparam int SDC_PNM		    =  SDC_OID+2;		    // ro: product name: 5 character
    localparam int SDC_PSN		    =  SDC_PNM+5;		    // ro: serial number: 32 bits unsigned
    localparam int SCC_ENABLE       =  16'h7E80;            // wo: enable disable SCC+
    localparam int SDC_END          =  16'h7EFF; 
    
    wire [8:0] sram_addr_w;
    reg ff_sram_we = 0;
    reg [7:0] ff_sram_cdin;
    reg [7:0] ff_sram_cdout;
    //
    reg ff_sd_en = 0;
    reg sram_cs_w;
    wire sram_busreq_w;
    wire [7:0] sram_cd_w;
    
    wire [3:0] sd_card_stat_w;
    wire [1:0] sd_card_type_w;
    reg ff_sd_rstart;
    reg ff_sd_init;
    reg [31:0] ff_sd_sector;
    wire sd_busy_w;
    wire sd_done_w;
    wire sd_outen_w;
    wire [8:0] sd_outaddr_w;
    wire [7:0] sd_outbyte_w;
    reg ff_sd_wstart;
    wire [7:0] sd_inbyte_w;
    
    wire [21:0] sd_c_size_w;
    wire [2:0] sd_c_size_mult_w;
    wire [3:0] sd_read_bl_len_w;
    
    wire [7:0] sd_mid_w;
    wire [15:0] sd_oid_w;
    wire [39:0] sd_pnm_w;
    wire [31:0] sd_psn_w;
    wire sd_crc_error_w;
    wire sd_timeout_error_w;
    //reg ff_scc_enable;
    //wire scc_enable_w;
    //assign scc_enable_w = ff_scc_enable;
    always @ (posedge clk_27m) begin
        sram_cs_w <= config_enable_sdcard == 1 && bus_reset_n && ff_sd_en && bus_iorq_n == 1 && bus_m1_n == 1 && bus_mreq_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && ( bus_addr >= SDC_SDATA && bus_addr < SDC_ENABLE) ? 1 : 0;
    end
    assign sram_busreq_w = sram_cs_w && ~bus_rd_n;
    
    dpram#(
        .widthad_a(9),
        .width_a(8)
    ) dpram1 (
        .clock_a(clk_27m),
        .wren_a(bus_clk_3m6_27 && sram_cs_w && ~bus_wr_n),
        .rden_a(bus_clk_3m6_27 && sram_cs_w && ~bus_rd_n),
        .address_a(bus_addr[8:0]),
        .data_a(cpu_dout),
        .q_a(sram_cd_w),
    
        .clock_b(clk_27m),
        .wren_b(ff_sd_rstart && sd_outen_w),
        .rden_b(ff_sd_wstart && sd_outen_w),
        .address_b(sd_outaddr_w),
        .data_b(sd_outbyte_w),
        .q_b(sd_inbyte_w)
    );
    
    sd_reader #(
        .CLK_DIV(3'd2),
        .SIMULATE(0)
    ) sd1 (
        .rstn(bus_reset_n),
        .clk(clk_27m),
        .sdclk(sd_sclk),
        .sdcmd(sd_cmd),
        .sddat0(sd_dat0),                  
        .card_stat(sd_card_stat_w),        // show the sdcard initialize status
        .card_type(sd_card_type_w),        // 0=UNKNOWN    , 1=SDv1    , 2=SDv2  , 3=SDHCv2
        .rstart(ff_sd_rstart), 
        .rsector(ff_sd_sector),
        .rbusy(sd_busy_w),
        .rdone(sd_done_w),
        .outen(sd_outen_w),                // when outen=1, a byte of sector content is read out from outbyte
        .outaddr(sd_outaddr_w),            // outaddr from 0 to 511, because the sector size is 512
        .outbyte(sd_outbyte_w),            // a byte of sector content
        .wstart(ff_sd_wstart), 
        .inbyte(sd_inbyte_w),
        .c_size(sd_c_size_w),
        .c_size_mult(sd_c_size_mult_w),
        .read_bl_len(sd_read_bl_len_w),
        .mid(sd_mid_w),
        .oid(sd_oid_w),
        .pnm(sd_pnm_w),
        .psn(sd_psn_w),
        .crc_error(sd_crc_error_w),
        .timeout_error(sd_timeout_error_w),
        .init(ff_sd_init)
    );
    
    assign sd_dat1 = 1;
    assign sd_dat2 = 1;
    assign sd_dat3 = 1; // Must set sddat1~3 to 1 to avoid SD card from entering SPI mode
    
    
    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            ff_sd_en <= 0;
        end else begin
            if (config_enable_sdcard == 1 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && bus_addr == SDC_ENABLE && ~bus_wr_n && bus_iorq_n && bus_m1_n) 
                ff_sd_en <= cpu_dout[0];
        end
    end
    
    reg sd_cs_w;
    always @ (posedge clk_27m) begin
        sd_cs_w <= config_enable_sdcard == 1 && bus_reset_n && ff_sd_en && bus_iorq_n && bus_m1_n && bus_mreq_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && (bus_addr >= SDC_ENABLE && bus_addr <= SDC_END) ? 1 : 0;
    end
    wire sd_busreq_w;
    assign sd_busreq_w = sd_cs_w && ~bus_rd_n;
    reg [7:0] ff_sd_cd;
    wire [7:0] sd_cd_w;
    assign sd_cd_w = ff_sd_cd;
    
    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            ff_sd_rstart <= '0;
            ff_sd_wstart <= '0;
            ff_sd_init <= '0;
        end else begin
            if (sd_done_w) begin
                ff_sd_rstart <= '0;
                ff_sd_wstart <= '0;
            end
    
            if (sd_cs_w) begin
                if (~bus_wr_n) begin
                    case(bus_addr) 
                        SDC_CMD: begin
                            ff_sd_rstart <= ff_sd_rstart | cpu_dout[0];
                            ff_sd_wstart <= ff_sd_wstart | cpu_dout[1];
                            ff_sd_init   <= ff_sd_init   | cpu_dout[7];
                            //ff_sms_init  <= ff_sms_init  | cdin_w[7];
                        end
                        SDC_SADDR+0:    ff_sd_sector[ 7: 0] <= cpu_dout;
                        SDC_SADDR+1:    ff_sd_sector[15: 8] <= cpu_dout;
                        SDC_SADDR+2:    ff_sd_sector[23:16] <= cpu_dout;
                        SDC_SADDR+3:    ff_sd_sector[31:24] <= cpu_dout;
                    endcase
                end else
                if (~bus_rd_n) begin
                    case(bus_addr) 
                        SDC_ENABLE:     ff_sd_cd <= { 7'b0, ff_sd_en };
                        SDC_STATUS:     ff_sd_cd <= { sd_busy_w, 5'b0, sd_timeout_error_w, sd_crc_error_w };
                        SDC_C_SIZE+0:   ff_sd_cd <= sd_c_size_w[7:0];
                        SDC_C_SIZE+1:   ff_sd_cd <= sd_c_size_w[15:8];
                        SDC_C_SIZE+2:   ff_sd_cd <= { 2'b0, sd_c_size_w[21:16] };
                        SDC_C_SIZE_MULT:ff_sd_cd <= { 5'b0, sd_c_size_mult_w };
                        SDC_RD_BL_LEN:  ff_sd_cd <= { 4'b0, sd_read_bl_len_w };
                        SDC_CTYPE:      ff_sd_cd <= { 6'b0, sd_card_type_w };
                        SDC_MID:        ff_sd_cd <= sd_mid_w;
                        SDC_OID+0:      ff_sd_cd <= sd_oid_w[7:0];
                        SDC_OID+1:      ff_sd_cd <= sd_oid_w[15:8];
                        SDC_PNM+0:      ff_sd_cd <= sd_pnm_w[7:0];
                        SDC_PNM+1:      ff_sd_cd <= sd_pnm_w[15:8];
                        SDC_PNM+2:      ff_sd_cd <= sd_pnm_w[23:16];
                        SDC_PNM+3:      ff_sd_cd <= sd_pnm_w[31:24];
                        SDC_PNM+4:      ff_sd_cd <= sd_pnm_w[39:32];
                        SDC_PSN+0:      ff_sd_cd <= sd_psn_w[7:0];
                        SDC_PSN+1:      ff_sd_cd <= sd_psn_w[15:8];
                        SDC_PSN+2:      ff_sd_cd <= sd_psn_w[23:16];
                        SDC_PSN+3:      ff_sd_cd <= sd_psn_w[31:24];
                        default:        ff_sd_cd <= '1;
                    endcase
                end
            end
        end
    end

`else

    wire sd_busreq_w = 1'b0;
    wire sram_busreq_w = 1'b0;
    wire megarom_req = 1'b0;
    wire megarom_page_req = 1'b0;
    wire sram_cs_w = 1'b0;
    wire sd_cs_w = 1'b0;
    assign sd_sclk = 1'b1;
    assign sd_dat1 = 1'b1;
    assign sd_dat2 = 1'b1;
    assign sd_dat3 = 1'b1;

`endif

`ifndef DIAG_SLIM
    // Switched I/O ports
    reg [1:0] Slot2Mode;
    wire  swio_req;
    wire [7:0] io42_id212;
    wire iSlt2_linear;
    wire swio_req;
    wire swio_req_r;
    wire swio_req_w;
    wire [7:0] swio_dout;
    assign swio_req_r = (config_enable_megaram == 1 && bus_addr[7:4] == 4'b0100 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign swio_req_w = (config_enable_megaram == 1 && bus_addr[7:4] == 4'b0100 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign swio_req = swio_req_r | swio_req_w;

    switched_io_ports ocm_ports (
            .clk21m        (clk_27m),
            .reset         (~bus_reset_n) ,
            .power_on_reset(1),
            .req           (swio_req   ),
            .ack           (           ),
            .wrt           (~bus_wr_n ),
            .adr           (bus_addr   ),
            .dbi           (swio_dout     ),
            .dbo           (cpu_dout      ),
            .io42_id212    (io42_id212    ),
            .iSlt2_linear  (iSlt2_linear  )
        );

    // virtual DIP-SW assignment (2/2)
    always @ ( posedge clk_27m )  begin
        Slot2Mode[1]    <=  io42_id212[4];
        Slot2Mode[0]    <=  io42_id212[5];
    end

    wire send;
    monostable mono2 (
        .pulse_in(s2),
        .clock(clk_27m),
        .pulse_out(send)
    );

//    msx2p_debug debug1 (
//        .clk_27m(clk_27m),
//        .clk (clk_27m),
//        .reset_n ( bus_reset_n ),
//        .clk_enable (clk_enable_3m6_27),
//        .bus_addr(bus_addr),
//        .bus_data(cpu_din),
//        .bus_iorq_n(bus_iorq_n),
//        .bus_mreq_n(bus_mreq_n),
//        .bus_wr_n(bus_wr_n),
//        .send(send),
//        .uart_tx(usb_uart_tx),
//        .boot_ok( )
//    );

    timing_debug debug1(
        .clk_27m(clk_27m),
        .clk_108m(clk_108m),
        .reset_n(bus_reset_n),
        .bus_iorq_n(ex_bus_iorq_n),
        .bus_mreq_n(ex_bus_mreq_n),
        .bus_rd_n(ex_bus_rd_n),
        .bus_wr_n(ex_bus_wr_n),
        .send(send),

        .uart_tx(usb_uart_tx)
    );
`else
    assign usb_uart_tx = 1'b1;              // Doctor: no debug UART
`endif

    bus_monitor busmon1 (
        .clk        (clk_54m),
        .reset_n    (bus_reset_n),
        .bus_data   (bus_data),
        .bus_addr   (bus_addr),
        .bus_m1_n   (bus_m1_n),
        .bus_rfsh_n (bus_rfsh_n),
        .bus_iorq_n (bus_iorq_n),
        .bus_mreq_n (bus_mreq_n),
        .bus_rd_n   (bus_rd_n),
        .bus_wr_n   (bus_wr_n),
        .bus_int_n  (bus_int_n),
        .bus_wait_n (bus_wait_n),
`ifdef DIAG_AUTOBOOT
        .clk_pin       (bus_clk_3m6_pin),
        .clk_using_int (diag_clk_use_int),
        .ex_reset_n    (ex_reset_n_f),
        .rst_edges     (diag_rst_edges),
`else
        .clk_pin       (bus_clk_3m6),
        .clk_using_int (1'b0),
        .ex_reset_n    (bus_reset_n),
        .rst_edges     (8'h00),
`endif
        .host_idx_in(cpu_dout),
        .sel_idx_we (busmon_idx_we),
        .sel_dat_re (busmon_dat_re),
        .sel_dat_we (busmon_dat_we),
        .host_dout  (busmon_dout),
`ifdef DIAG_AUTOBOOT
        .ctrl_slot0_ext (diag_ctl_slot0),
        .ctrl_vdp_ext   (diag_vdp_ext),
        .ctrl_ign_int   (diag_ign_int),
        .ctrl_ign_wait  (diag_ign_wait),
        .ctrl_ppi_ext   (diag_ppi_ext),
        .ctrl_rtc_ext   (diag_rtc_ext),
        .ctrl_kbd_usb_off  (diag_kbd_usb_off),
        .ctrl_kbd_phys_off (diag_kbd_phys_off),
        .ctrl_trans     (diag_trans),
        .ctrl_p3_release(diag_p3_release),
        .wait_stuck     (diag_wait_stuck)
`else
        .ctrl_slot0_ext (),
        .ctrl_vdp_ext   (),
        .ctrl_ign_int   (),
        .ctrl_ign_wait  (),
        .ctrl_ppi_ext   (),
        .ctrl_rtc_ext   (),
        .ctrl_kbd_usb_off  (),
        .ctrl_kbd_phys_off (),
        .ctrl_trans     (),
        .ctrl_p3_release(),
        .wait_stuck     ()
`endif
    );


endmodule