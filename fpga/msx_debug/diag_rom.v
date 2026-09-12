// 16 KB synchronous ROM holding the diagnostic cartridge image (slot 0-3 page 1)
//
// Eight explicit 2048x8 banks, one BSRAM primitive each with its own
// $readmemh, and a registered output mux: a single 16384x8 array with one
// $readmemh spans 8 primitives and the Gowin init of such arrays is not to be
// trusted (see MSXnano tape_rom: only the first primitive came out right).
// The split files diag_rom_0.hex .. diag_rom_7.hex are produced by
// diag/tools/split_rom_hex.py from DIAG.ROM.  Read latency: 2 clocks.
module diag_rom (
    input  wire        clk,
    input  wire [13:0] addr,
    output reg  [7:0]  dout
);
    reg [7:0] bank0 [0:2047];
    reg [7:0] bank1 [0:2047];
    reg [7:0] bank2 [0:2047];
    reg [7:0] bank3 [0:2047];
    reg [7:0] bank4 [0:2047];
    reg [7:0] bank5 [0:2047];
    reg [7:0] bank6 [0:2047];
    reg [7:0] bank7 [0:2047];
    initial $readmemh("msx_debug/diag_rom_0.hex", bank0);
    initial $readmemh("msx_debug/diag_rom_1.hex", bank1);
    initial $readmemh("msx_debug/diag_rom_2.hex", bank2);
    initial $readmemh("msx_debug/diag_rom_3.hex", bank3);
    initial $readmemh("msx_debug/diag_rom_4.hex", bank4);
    initial $readmemh("msx_debug/diag_rom_5.hex", bank5);
    initial $readmemh("msx_debug/diag_rom_6.hex", bank6);
    initial $readmemh("msx_debug/diag_rom_7.hex", bank7);

    reg [7:0] q0, q1, q2, q3, q4, q5, q6, q7;
    reg [2:0] sel;
    always @(posedge clk) begin
        q0  <= bank0[addr[10:0]];
        q1  <= bank1[addr[10:0]];
        q2  <= bank2[addr[10:0]];
        q3  <= bank3[addr[10:0]];
        q4  <= bank4[addr[10:0]];
        q5  <= bank5[addr[10:0]];
        q6  <= bank6[addr[10:0]];
        q7  <= bank7[addr[10:0]];
        sel <= addr[13:11];
        case (sel)
            3'd0: dout <= q0;
            3'd1: dout <= q1;
            3'd2: dout <= q2;
            3'd3: dout <= q3;
            3'd4: dout <= q4;
            3'd5: dout <= q5;
            3'd6: dout <= q6;
            default: dout <= q7;
        endcase
    end
endmodule
