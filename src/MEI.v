// Não tratamos pc > tamanho*4
module MEI #(
    parameter TAMANHO = 256 // tamanho da memoria em numeros de palavra
)(
    input wire clk,
    input wire rst,

    input wire [9:0] pc,              
    output reg [31:0] saida0, // instrução = [31-0], numero de ordem = [63-32]
    output reg [31:0] saida1,
    output reg [31:0] saida2
);
    //IVAN FEATURE: A MEI é só memória. Os PCs de cada slot e a previsão de desvio
    //(BTB) ficam fora dela, no controle da busca.
    reg [31:0] memoria [TAMANHO-1:0]; // largura * profundidade

    always @(posedge clk) begin
        if (rst) begin
            saida0   <= 32'b0;
            saida1   <= 32'b0;
            saida2   <= 32'b0;
        end else begin
            saida0 <= memoria[pc >> 2];
            saida1 <= memoria[(pc >> 2) + 10'b1];
            saida2 <= memoria[(pc >> 2) + 10'b10];
        end
    end
endmodule
