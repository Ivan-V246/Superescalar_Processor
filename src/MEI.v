//==============================================================================
// MEI — Memória de Instruções
//
// 256 palavras de 32 bits; o pc (10 bits) endereça bytes, então a palavra
// lida é pc >> 2. O programa é carregado pelo testbench ($readmemh).
//
// Leitura registrada de 3 instruções por ciclo: recebe o pc do próximo grupo
// (pc_prox, no topo) e, na borda do clock, entrega as instruções em pc, pc+4
// e pc+8, junto com o pc de cada uma. O pc vai para o despacho (AUIPC e
// desvios) e para a consulta ao BTB.
//
// A MEI não decide o próximo pc nem guarda previsão: isso fica no topo
// (pc_prox), no BTB e no despacho.
//
// PREMISSA: pc + 8 < TAMANHO*4. Acima disso, a instrução lida é indefinida (x).
//==============================================================================

module MEI #(
    parameter TAMANHO = 256 // Tamanho da memória em palavras
)(
    input wire clk,
    input wire rst,

    input wire [9:0] pc,             // pc do grupo a ler (pc_prox no topo)
    output reg [31:0] saida0,        // Instrução em pc
    output reg [31:0] saida1,        // Instrução em pc + 4
    output reg [31:0] saida2,        // Instrução em pc + 8
    output reg [9:0]  pc0, pc1, pc2  // pc de cada instrução, registrado junto com ela
);

    reg [31:0] memoria [TAMANHO-1:0]; // largura * profundidade

    always @(posedge clk) begin
        if (rst) begin
            saida0 <= 32'b0;
            saida1 <= 32'b0;
            saida2 <= 32'b0;
            pc0 <= 10'd0; pc1 <= 10'd0; pc2 <= 10'd0;
        end else begin
            saida0 <= memoria[pc >> 2];
            saida1 <= memoria[(pc >> 2) + 10'd1];
            saida2 <= memoria[(pc >> 2) + 10'd2];
            pc0 <= pc; pc1 <= pc + 10'd4; pc2 <= pc + 10'd8;
        end
    end
endmodule
