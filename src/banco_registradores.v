`timescale 1ns/1ps
// Banco arquitetural RV32I: 32 x 32 bits, seis leituras e tres escritas.
// Leitura combinacional, sem bypass; escrita e reset na borda positiva.
// Depois da borda, as leituras refletem a atualizacao dos registradores.
// Um consumidor que captura NA MESMA borda ainda recebe o valor anterior.
module banco_registradores (
    input wire clk, rst,

    input wire [4:0] rs1_1, rs2_1,
    input wire [4:0] rs1_2, rs2_2,
    input wire [4:0] rs1_3, rs2_3,
    output wire [31:0] valor_rs1_1, valor_rs2_1,
    output wire [31:0] valor_rs1_2, valor_rs2_2,
    output wire [31:0] valor_rs1_3, valor_rs2_3,

    // Portas 1, 2, 3 em ordem de aposentadoria: antiga -> nova.
    input wire [2:0] we,
    input wire [4:0] rd1, rd2, rd3,
    input wire [31:0] dado1, dado2, dado3
);
    reg [31:0] registradores [0:31];

    // x0 e constante, inclusive antes da primeira borda de reset.
    assign valor_rs1_1 = (rs1_1 == 5'd0) ? 32'd0 : registradores[rs1_1];
    assign valor_rs2_1 = (rs2_1 == 5'd0) ? 32'd0 : registradores[rs2_1];
    assign valor_rs1_2 = (rs1_2 == 5'd0) ? 32'd0 : registradores[rs1_2];
    assign valor_rs2_2 = (rs2_2 == 5'd0) ? 32'd0 : registradores[rs2_2];
    assign valor_rs1_3 = (rs1_3 == 5'd0) ? 32'd0 : registradores[rs1_3];
    assign valor_rs2_3 = (rs2_3 == 5'd0) ? 32'd0 : registradores[rs2_3];

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                registradores[i] <= 32'd0;
        end else begin
            // A ultima atribuicao valida prevalece em colisoes: 3 > 2 > 1.
            if (we[0] && rd1 != 5'd0) registradores[rd1] <= dado1;
            if (we[1] && rd2 != 5'd0) registradores[rd2] <= dado2;
            if (we[2] && rd3 != 5'd0) registradores[rd3] <= dado3;
        end
    end
endmodule
