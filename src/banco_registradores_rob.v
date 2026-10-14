`timescale 1ns/1ps
// Adaptador para os commits do ROB e os dados compactados do Load Buffer.
// dst: 000=nada, 001=banco, 010=load, 011=banco+pc, 100=store.
// 101, 110 e 111 sao reservados nesta versao e nao habilitam escritas.
// Contrato: os loads aposentados ja estao prontos e ordenados no LB.
// Esta interface nao recebe flags de prontidao nem IDs dos dados do LB;
// o testbench de integracao verifica esse contrato antes de cada escrita.
module banco_registradores_rob (
    input wire clk, rst,
    input wire [4:0] rs1_1, rs2_1,
    input wire [4:0] rs1_2, rs2_2,
    input wire [4:0] rs1_3, rs2_3,
    output wire [31:0] valor_rs1_1, valor_rs2_1,
    output wire [31:0] valor_rs1_2, valor_rs2_2,
    output wire [31:0] valor_rs1_3, valor_rs2_3,

    input wire [2:0] cdst1, cdst2, cdst3,
    input wire [4:0] crid1, crid2, crid3,
    input wire [31:0] cr1, cr2, cr3,
    input wire [31:0] lb_dado1, lb_dado2, lb_dado3
);
    function escreve_registrador;
        input [2:0] destino;
        begin
            case (destino)
                3'b001, 3'b010, 3'b011: escreve_registrador = 1'b1;
                // Inclui nada, store, codigos reservados e desconhecidos.
                default: escreve_registrador = 1'b0;
            endcase
        end
    endfunction

    wire load1 = cdst1 == 3'b010;
    wire load2 = cdst2 == 3'b010;
    wire load3 = cdst3 == 3'b010;
    wire [2:0] we = {
        escreve_registrador(cdst3), escreve_registrador(cdst2), escreve_registrador(cdst1)
    };

    // Os dados do LB sao os tres loads mais antigos, nao os tres slots ROB.
    // Ex.: banco/load/load usa cr1/lb_dado1/lb_dado2.
    wire [31:0] dado1 = load1 ? lb_dado1 : cr1;
    wire [31:0] dado2 = load2 ? (load1 ? lb_dado2 : lb_dado1) : cr2;
    wire [31:0] dado3 = load3 ?
        ((load1 && load2) ? lb_dado3 :
         ((load1 || load2) ? lb_dado2 : lb_dado1)) : cr3;

    banco_registradores banco (
        .clk(clk), .rst(rst),
        .rs1_1(rs1_1), .rs2_1(rs2_1), .rs1_2(rs1_2), .rs2_2(rs2_2),
        .rs1_3(rs1_3), .rs2_3(rs2_3),
        .valor_rs1_1(valor_rs1_1), .valor_rs2_1(valor_rs2_1),
        .valor_rs1_2(valor_rs1_2), .valor_rs2_2(valor_rs2_2),
        .valor_rs1_3(valor_rs1_3), .valor_rs2_3(valor_rs2_3),
        .we(we), .rd1(crid1), .rd2(crid2), .rd3(crid3),
        .dado1(dado1), .dado2(dado2), .dado3(dado3)
    );
endmodule
