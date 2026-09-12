//============================================================================
//  bus_monitor.v  -  Goa'uld Z80-socket bus line monitor / verifier  (v2)
//----------------------------------------------------------------------------
//  Passive, always-on observer of the real MSX system bus as it arrives at the
//  FPGA pins (the Z80 socket). It accumulates line-level health information and
//  exposes it to the FPGA's own Z80 through two internal I/O ports, so a normal
//  MSX diagnostic program (running on the Goa'uld's internal VDP/BIOS) can read
//  it and paint the results on the HDMI screen.
//
//  It does NOT drive the bus. The Z80 core (T80) keeps generating all the real
//  bus cycles (cartridge reads, RAM, PPI, ...) with its already-validated
//  address-mux + data-transceiver timing; this module only watches the lines
//  during those cycles and answers IN instructions.
//
//  v2 ("Goa'uld Doctor") adds:
//    * board clock liveness + frequency, external /RESET level and edge count,
//      stuck-/WAIT detection and a free-running millisecond counter (0x15-0x1A)
//    * a CONTROL register (0x20) that lets the diagnostic ROM steer the core:
//      make the board's physical slot 0 visible (BIOS + RAM test), route the
//      VDP ports to the board's own VDP (VRAM test), read the board's PPI, and
//      mask /INT and /WAIT while a test runs.
//
//  Everything runs in clk_54m, the same domain that already feeds `bus_data`,
//  the synchronized control inputs and the cpu_din mux in top.v, so there is
//  no clock-domain crossing to get wrong.
//
//----------------------------------------------------------------------------
//  Host (Z80) interface  -  index / data register pair
//----------------------------------------------------------------------------
//    OUT (0x2C), n   -> select register index n                   (sel_idx_we)
//    IN  (0x2D)      -> read regs[idx], then idx++                (sel_dat_re)
//    OUT (0x2D), x   -> idx == 0x20 : write CONTROL register      (sel_dat_we)
//                       otherwise   : clear / re-arm all accumulators
//
//  Ports wired in top.v: IDX_PORT=0x2C, DAT_PORT=0x2D (read-served
//  internally via the cpu_din mux). Block-read the whole register file by
//  doing OUT(0x2C),0 then repeated IN(0x2D) thanks to the auto-increment.
//
//----------------------------------------------------------------------------
//  Register map (read through DAT_PORT)
//----------------------------------------------------------------------------
//   0x00 SIGNATURE      0x42 ('B')        - presence / sanity check
//   0x01 VERSION        0x02
//   0x02 D_DEAD_LO      D7..D0 : 1 = data line NEVER seen HIGH during a read
//                                (stuck-0 / open / not reaching the socket)
//   0x03 D_DEAD_HI      D7..D0 : 1 = data line NEVER seen LOW  during a read
//                                (stuck-1)
//   0x04 D_LAST         last data byte latched on a completed read cycle
//   0x05 A_DEAD_LO_L    A7..A0  : 1 = addr line never seen HIGH during a cycle
//   0x06 A_DEAD_LO_H    A15..A8 : 1 = addr line never seen HIGH
//   0x07 A_DEAD_HI_L    A7..A0  : 1 = addr line never seen LOW
//   0x08 A_DEAD_HI_H    A15..A8 : 1 = addr line never seen LOW
//   0x09 LAST_IO_PORT   low addr byte of the last I/O (IORQ) access
//   0x0A LAST_IO_DATA   data byte seen on the last I/O access
//   0x0B LAST_A_L       low  byte of last address with bus activity
//   0x0C LAST_A_H       high byte of last address with bus activity
//   0x0D CTRL_LIVE      live control levels (active-low, as on the pins):
//                       bit7 RFSH_n bit6 M1_n bit5 WAIT_n bit4 INT_n
//                       bit3 RESET_n bit2 MREQ_n bit1 IORQ_n bit0 RD_n
//   0x0E INT_RATE       /INT falling edges in last ~1 s  (saturating 0xFF)
//                       ~50 (PAL) / ~60 (NTSC) expected; 0 = /INT not arriving
//   0x0F WAIT_CNT       /WAIT assertions, saturating 0xFF (0 = never waited)
//   0x10 WAIT_MAXLEN    longest /WAIT stretch in clk_54m ticks (sat 0xFF)
//   0x11 IORQ_CNT_L     I/O cycle counter low   (proof of bus life)
//   0x12 IORQ_CNT_H     I/O cycle counter high
//   0x13 MREQ_CNT_L     memory cycle counter low
//   0x14 MREQ_CNT_H     memory cycle counter high
//   ---- v2 ----
//   0x15 SYS_STAT       bit0 board clock alive (edges seen on the socket pin)
//                       bit1 core running on the INTERNAL fallback clock
//                       bit2 external /RESET pin level (1 = idle/high)
//                       bit3 /WAIT stuck low (auto-released, see top.v)
//                       bit4 external /WAIT pin level (1 = idle)
//                       bit5 external /INT pin level (1 = idle)
//                       bit6 CONTROL.slot0_ext echo
//                       bit7 CONTROL.vdp_ext echo
//   0x16 CLK_L          board clock rising edges in the last 10 ms window, low
//   0x17 CLK_H          ... high  (35795 = 3579.5 kHz; 0 = no clock)
//   0x18 RST_EDGES      external /RESET falling edges since FPGA config (sat)
//   0x19 MS_L           free-running millisecond counter, low byte
//   0x1A MS_H           high byte, LATCHED when MS_L is read (torn-safe)
//   0x20 CONTROL        (R/W)  bit0 slot0_ext : physical slot 0 visible
//                              bit1 vdp_ext   : VDP ports -> board's VDP
//                              bit2 ign_int   : mask external /INT to core
//                              bit3 ign_wait  : mask external /WAIT to core
//                              bit4 ppi_ext   : read PPI port A (0xA8) from bus
//                              bit5 rtc_ext   : RTC I/O 0xB4-0xB5 reads from bus
//                              bit6 kbd_usb_off : drop the USB keyboard from IN 0xA9
//                              bit7 kbd_phys_off: drop the board keyboard from IN 0xA9
//   0x21 CONTROL2       (R/W)  bits3:0 transparency mask, one bit per primary
//                              slot: memory reads of that slot come from the
//                              bus even where the Goa'uld has internal devices
//                              (except the Doctor ROM 0-3 page 1 and the
//                              internal mapper 3-0 page 3, see bit4)
//                              bit4 p3_release: also hand 3-0 page 3 to the bus
//                              (stackless page-3 test of a board RAM in 3-0)
//   others -> 0x00
//============================================================================

module bus_monitor (
    input  wire        clk,          // clk_54m
    input  wire        reset_n,      // bus_reset_n (sync)

    // --- observed bus (already synchronized in top.v) ---
    input  wire [7:0]  bus_data,
    input  wire [15:0] bus_addr,
    input  wire        bus_m1_n,
    input  wire        bus_rfsh_n,
    input  wire        bus_iorq_n,
    input  wire        bus_mreq_n,
    input  wire        bus_rd_n,
    input  wire        bus_wr_n,
    input  wire        bus_int_n,
    input  wire        bus_wait_n,

    // --- v2: board-level health inputs (from top.v) ---
    input  wire        clk_pin,        // filtered board clock as seen on the pin
    input  wire        clk_using_int,  // 1 = core runs on the internal fallback
    input  wire        ex_reset_n,     // filtered external /RESET level
    input  wire [7:0]  rst_edges,      // /RESET falling edges since config

    // --- host (Z80) register interface, level signals from top.v decode ---
    input  wire [7:0]  host_idx_in,  // value on OUT (IDX_PORT) / OUT (DAT_PORT)
    input  wire        sel_idx_we,   // 1 while OUT (IDX_PORT) is active
    input  wire        sel_dat_re,   // 1 while IN  (DAT_PORT) is active
    input  wire        sel_dat_we,   // 1 while OUT (DAT_PORT) is active

    output reg  [7:0]  host_dout,

    // --- v2: control outputs to top.v ---
    output wire        ctrl_slot0_ext,
    output wire        ctrl_vdp_ext,
    output wire        ctrl_ign_int,
    output wire        ctrl_ign_wait,
    output wire        ctrl_ppi_ext,
    output wire        ctrl_rtc_ext,
    output wire        ctrl_kbd_usb_off,
    output wire        ctrl_kbd_phys_off,
    output wire [3:0]  ctrl_trans,      // CONTROL2 transparency mask
    output wire        ctrl_p3_release,
    output reg         wait_stuck
);

    // ----- 1 second tick (clk_54m = 54 MHz) -----
    // ONE_SEC is a parameter so a testbench can shrink the window and exercise
    // INT_RATE in a short sim. Default (54e6) is correct for synthesis.
    parameter  ONE_SEC = 32'd54_000_000;
    reg [31:0] sec_cnt = 32'd0;
    wire       sec_tic = (sec_cnt == 32'd0);
    always @(posedge clk) begin
        sec_cnt <= (sec_cnt >= ONE_SEC - 1) ? 32'd0 : sec_cnt + 32'd1;
    end

    // ----- 1 ms tick (54000 clocks) and 10 ms window (10 ms ticks) -----
    // Registered terminal-count flags keep the wide comparators off the
    // increment carry chain (GW2A @ 54 MHz lesson).
    parameter  ONE_MS = 16'd54_000;
    reg [15:0] ms_div  = 16'd0;
    reg        ms_tic  = 1'b0;
    reg [3:0]  ten_cnt = 4'd0;
    reg        win10_tic = 1'b0;
    always @(posedge clk) begin
        ms_tic <= (ms_div == ONE_MS - 2);
        ms_div <= ms_tic ? 16'd0 : ms_div + 16'd1;
        win10_tic <= 1'b0;
        if (ms_tic) begin
            if (ten_cnt == 4'd9) begin
                ten_cnt   <= 4'd0;
                win10_tic <= 1'b1;
            end
            else
                ten_cnt <= ten_cnt + 4'd1;
        end
    end

    // ----- edge / activity detect -----
    reg rd_n_d, iorq_n_d, mreq_n_d, int_n_d, wait_n_d, clk_pin_d;
    always @(posedge clk) begin
        rd_n_d    <= bus_rd_n;
        iorq_n_d  <= bus_iorq_n;
        mreq_n_d  <= bus_mreq_n;
        int_n_d   <= bus_int_n;
        wait_n_d  <= bus_wait_n;
        clk_pin_d <= clk_pin;
    end
    wire read_valid   = (~bus_rd_n) & ((~bus_iorq_n) | (~bus_mreq_n)); // device drives data
    wire cycle_active = (~bus_iorq_n) | ((~bus_mreq_n) & bus_rfsh_n);  // real M/IO cycle, ignore refresh
    wire rd_falling   = rd_n_d   & ~bus_rd_n;
    wire rd_rising    = ~rd_n_d  &  bus_rd_n;   // read just finished
    wire iorq_falling = iorq_n_d & ~bus_iorq_n;
    wire mreq_falling = mreq_n_d & ~bus_mreq_n & bus_rfsh_n;
    wire int_falling  = int_n_d  & ~bus_int_n;
    wire wait_falling = wait_n_d & ~bus_wait_n;
    wire clk_rising   = ~clk_pin_d & clk_pin;

    // ----- accumulators -----
    reg [7:0]  d_seen_hi,  d_seen_lo;     // data lines that have been hi / lo
    reg [15:0] a_seen_hi,  a_seen_lo;     // address lines hi / lo
    reg [7:0]  d_last;
    reg [7:0]  last_io_port, last_io_data;
    reg [15:0] last_addr;
    reg [7:0]  int_rate_run, int_rate_lat;
    reg [7:0]  wait_cnt;
    reg [7:0]  wait_len, wait_maxlen;
    reg [15:0] iorq_cnt, mreq_cnt;
    reg        clear_req;

    // ----- v2 registers -----
    reg [7:0]  ctrl;                       // CONTROL register
    reg [7:0]  ctrl2;                      // CONTROL2 register
    reg [15:0] clk_run, clk_lat;           // board clock edges / 10 ms window
    reg        clk_alive;                  // any edge in the last 10 ms window
    reg [15:0] ms_cnt;                     // free-running ms counter
    reg [7:0]  ms_h_lat;                   // MS_H latched on MS_L read
    reg [16:0] wait_low_cnt;               // /WAIT continuously-low length

    assign ctrl_slot0_ext = ctrl[0];
    assign ctrl_vdp_ext   = ctrl[1];
    assign ctrl_ign_int   = ctrl[2];
    assign ctrl_ign_wait  = ctrl[3];
    assign ctrl_ppi_ext   = ctrl[4];
    assign ctrl_rtc_ext   = ctrl[5];
    assign ctrl_kbd_usb_off  = ctrl[6];
    assign ctrl_kbd_phys_off = ctrl[7];
    assign ctrl_trans     = ctrl2[3:0];
    assign ctrl_p3_release = ctrl2[4];

    // host write to DAT_PORT: CONTROL when idx==0x20, else re-arm the window
    reg [7:0] idx = 8'h00;
    reg       dat_we_d;
    wire      dat_we_pulse = sel_dat_we & ~dat_we_d;
    always @(posedge clk) begin
        dat_we_d  <= sel_dat_we;
        clear_req <= dat_we_pulse & (idx != 8'h20) & (idx != 8'h21);
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            d_seen_hi    <= 8'h00;  d_seen_lo    <= 8'h00;
            a_seen_hi    <= 16'h0;  a_seen_lo    <= 16'h0;
            d_last       <= 8'h00;
            last_io_port <= 8'h00;  last_io_data <= 8'h00;
            last_addr    <= 16'h0;
            int_rate_run <= 8'h00;  int_rate_lat <= 8'h00;
            wait_cnt     <= 8'h00;
            wait_len     <= 8'h00;  wait_maxlen  <= 8'h00;
            iorq_cnt     <= 16'h0;  mreq_cnt     <= 16'h0;
            ctrl         <= 8'h00;  ctrl2        <= 8'h00;
            clk_run      <= 16'h0;  clk_lat      <= 16'h0;
            clk_alive    <= 1'b0;
            ms_cnt       <= 16'h0;  ms_h_lat     <= 8'h00;
            wait_low_cnt <= 17'd0;  wait_stuck   <= 1'b0;
        end
        else begin
            // window clear / re-arm
            if (clear_req) begin
                d_seen_hi <= 8'h00;  d_seen_lo <= 8'h00;
                a_seen_hi <= 16'h0;  a_seen_lo <= 16'h0;
                wait_cnt  <= 8'h00;  wait_maxlen <= 8'h00;
                iorq_cnt  <= 16'h0;  mreq_cnt  <= 16'h0;
            end

            // CONTROL register write (OUT (0x2D) while idx == 0x20)
            if (dat_we_pulse && idx == 8'h20) ctrl  <= host_idx_in;
            if (dat_we_pulse && idx == 8'h21) ctrl2 <= host_idx_in;

            // data-line liveness, sampled while a device is driving the bus
            if (read_valid) begin
                d_seen_hi <= d_seen_hi |  bus_data;
                d_seen_lo <= d_seen_lo | ~bus_data;
            end
            // address-line liveness, sampled during any real cycle
            if (cycle_active) begin
                a_seen_hi <= a_seen_hi |  bus_addr;
                a_seen_lo <= a_seen_lo | ~bus_addr;
                last_addr <= bus_addr;
            end

            // latch last read byte when the read cycle ends
            if (rd_rising) d_last <= bus_data;

            // I/O transaction snapshot + counter
            if (iorq_falling & bus_m1_n) begin           // skip M1 (interrupt ack)
                last_io_port <= bus_addr[7:0];
                iorq_cnt     <= iorq_cnt + 16'd1;
            end
            if (read_valid & ~bus_iorq_n) last_io_data <= bus_data;
            if (mreq_falling) mreq_cnt <= mreq_cnt + 16'd1;

            // /INT rate per 1 s window
            if (int_falling && int_rate_run != 8'hFF) int_rate_run <= int_rate_run + 8'd1;
            if (sec_tic) begin
                int_rate_lat <= int_rate_run;
                int_rate_run <= 8'h00;
            end

            // /WAIT statistics. wait_len counts cycles already seen; the length
            // INCLUDING the current asserted cycle is wait_len+1, so a 1-cycle
            // wait reports 1 (not 0, which would alias "never waited"). Saturate.
            if (wait_falling && wait_cnt != 8'hFF) wait_cnt <= wait_cnt + 8'd1;
            if (~bus_wait_n) begin
                if (wait_len != 8'hFF) wait_len <= wait_len + 8'd1;
                if (wait_len == 8'hFF)
                    wait_maxlen <= 8'hFF;
                else if ((wait_len + 8'd1) > wait_maxlen)
                    wait_maxlen <= wait_len + 8'd1;
            end
            else begin
                wait_len <= 8'h00;
            end

            // /WAIT stuck low: no MSX device holds /WAIT for more than a few us.
            // After ~1.2 ms continuously low we flag it (top.v releases the core
            // so the diagnostic can still run and REPORT it). Self-clearing.
            if (bus_wait_n) begin
                wait_low_cnt <= 17'd0;
                wait_stuck   <= 1'b0;
            end
            else if (wait_low_cnt[16])
                wait_stuck   <= 1'b1;
            else
                wait_low_cnt <= wait_low_cnt + 17'd1;

            // board clock: rising edges per 10 ms window (35795 @ 3.579545 MHz)
            if (clk_rising && clk_run != 16'hFFFF) clk_run <= clk_run + 16'd1;
            if (win10_tic) begin
                clk_lat   <= clk_run;
                clk_alive <= (clk_run != 16'h0);
                clk_run   <= 16'h0;
            end

            // free-running millisecond counter, high byte latched on MS_L read
            if (ms_tic) ms_cnt <= ms_cnt + 16'd1;
            if (sel_dat_re && idx == 8'h19) ms_h_lat <= ms_cnt[15:8];
        end
    end

    // derived "dead line" masks: a line is dead if it never reached one level
    wire [7:0]  d_dead_lo = ~d_seen_hi;   // never went high
    wire [7:0]  d_dead_hi = ~d_seen_lo;   // never went low
    wire [15:0] a_dead_lo = ~a_seen_hi;
    wire [15:0] a_dead_hi = ~a_seen_lo;

    wire [7:0] ctrl_live = { bus_rfsh_n, bus_m1_n, bus_wait_n, bus_int_n,
                             reset_n,    bus_mreq_n, bus_iorq_n, bus_rd_n };

    wire [7:0] sys_stat  = { ctrl[1], ctrl[0], bus_int_n, bus_wait_n,
                             wait_stuck, ex_reset_n, clk_using_int, clk_alive };

    // ----- register index with auto-increment -----
    reg       dat_re_d;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            idx      <= 8'h00;
            dat_re_d <= 1'b0;
        end
        else begin
            dat_re_d <= sel_dat_re;
            if (sel_idx_we)            idx <= host_idx_in;     // explicit index set
            else if (dat_re_d & ~sel_dat_re) idx <= idx + 8'd1; // auto-inc after read ends
        end
    end

    always @(*) begin
        case (idx)
            8'h00:   host_dout = 8'h42;          // 'B'
            8'h01:   host_dout = 8'h02;          // version
            8'h02:   host_dout = d_dead_lo;
            8'h03:   host_dout = d_dead_hi;
            8'h04:   host_dout = d_last;
            8'h05:   host_dout = a_dead_lo[7:0];
            8'h06:   host_dout = a_dead_lo[15:8];
            8'h07:   host_dout = a_dead_hi[7:0];
            8'h08:   host_dout = a_dead_hi[15:8];
            8'h09:   host_dout = last_io_port;
            8'h0A:   host_dout = last_io_data;
            8'h0B:   host_dout = last_addr[7:0];
            8'h0C:   host_dout = last_addr[15:8];
            8'h0D:   host_dout = ctrl_live;
            8'h0E:   host_dout = int_rate_lat;
            8'h0F:   host_dout = wait_cnt;
            8'h10:   host_dout = wait_maxlen;
            8'h11:   host_dout = iorq_cnt[7:0];
            8'h12:   host_dout = iorq_cnt[15:8];
            8'h13:   host_dout = mreq_cnt[7:0];
            8'h14:   host_dout = mreq_cnt[15:8];
            8'h15:   host_dout = sys_stat;
            8'h16:   host_dout = clk_lat[7:0];
            8'h17:   host_dout = clk_lat[15:8];
            8'h18:   host_dout = rst_edges;
            8'h19:   host_dout = ms_cnt[7:0];
            8'h1A:   host_dout = ms_h_lat;
            8'h20:   host_dout = ctrl;
            8'h21:   host_dout = ctrl2;
            default: host_dout = 8'h00;
        endcase
    end

endmodule
