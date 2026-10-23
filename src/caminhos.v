// Tres caminhos paralelos: o slot k do despacho vai para o caminho k
module caminhos (
    input  wire        clk, rst,

    // Despacho
    input  wire [2:0]  v,
    input  wire [31:0] instr1, instr2, instr3,
    input  wire [31:0] valor_rs1_1, valor_rs2_1,
    input  wire [31:0] valor_rs1_2, valor_rs2_2,
    input  wire [31:0] valor_rs1_3, valor_rs2_3,
    input  wire [4:0]  rob_id1, rob_id2, rob_id3,
    output wire [2:0]  ready,

    // ROB
    output wire [2:0]  wb,
    output wire [4:0]  rid1, rid2, rid3,
    output wire [31:0] r1, r2, r3
);
    caminho c1 (
        .clk(clk), .rst(rst),
        .valido(v[0]), .instr(instr1),
        .valor_rs1(valor_rs1_1), .valor_rs2(valor_rs2_1),
        .rob_id(rob_id1), .ready(ready[0]),
        .wb(wb[0]), .rid(rid1), .r(r1)
    );

    caminho c2 (
        .clk(clk), .rst(rst),
        .valido(v[1]), .instr(instr2),
        .valor_rs1(valor_rs1_2), .valor_rs2(valor_rs2_2),
        .rob_id(rob_id2), .ready(ready[1]),
        .wb(wb[1]), .rid(rid2), .r(r2)
    );

    caminho c3 (
        .clk(clk), .rst(rst),
        .valido(v[2]), .instr(instr3),
        .valor_rs1(valor_rs1_3), .valor_rs2(valor_rs2_3),
        .rob_id(rob_id3), .ready(ready[2]),
        .wb(wb[2]), .rid(rid3), .r(r3)
    );
endmodule
