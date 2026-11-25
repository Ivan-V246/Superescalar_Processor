//==============================================================================
// Banco de Registradores
//
// Banco arquitetural RV32I: 32 registradores de 32 bits, com seis leituras e
// três escritas por ciclo.
//
//   - Leitura (combinacional, sem bypass): duas portas (rs1, rs2) para cada um
//     dos três caminhos. x0 sempre lê 0, inclusive antes do primeiro reset.
//   - Escrita (na borda do clock): até três commits do ROB por ciclo, em ordem
//     de programa. Escritas em x0 são ignoradas. Se dois commits do mesmo
//     ciclo escrevem o mesmo registrador, vale o mais novo (3 > 2 > 1).
//
// Sem bypass: depois da borda, as leituras já mostram o valor novo, mas quem
// captura na mesma borda ainda recebe o anterior. O valor de uma instrução
// ainda não commitada vem do hazard (forwarding), não do banco.
//==============================================================================

module banco_registradores (
    input wire clk, rst,

    //---- Leitura: despacho envia os números, caminhos recebem os valores ----
    input  wire [4:0]  rs1_1, rs2_1,               // Caminho 1 (comum)
    input  wire [4:0]  rs1_2, rs2_2,               // Caminho 2 (comum)
    input  wire [4:0]  rs1_3, rs2_3,               // Caminho 3 (desvio)
    output wire [31:0] valor_rs1_1, valor_rs2_1,
    output wire [31:0] valor_rs1_2, valor_rs2_2,
    output wire [31:0] valor_rs1_3, valor_rs2_3,

    //---- Escrita: commits do ROB, em ordem (1 = mais antigo, 3 = mais novo) ----
    input  wire [2:0]  we,                         // Quais commits escrevem
    input  wire [4:0]  rd1, rd2, rd3,              // Registrador de destino
    input  wire [31:0] dado1, dado2, dado3         // Valor (resultado ou dado do Load)
);
    reg [31:0] registradores [0:31];

    // x0 é constante, inclusive antes da primeira borda de reset.
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
            // A última atribuição válida prevalece em colisões: 3 > 2 > 1.
            if (we[0] && rd1 != 5'd0) registradores[rd1] <= dado1;
            if (we[1] && rd2 != 5'd0) registradores[rd2] <= dado2;
            if (we[2] && rd3 != 5'd0) registradores[rd3] <= dado3;
        end
    end
endmodule
