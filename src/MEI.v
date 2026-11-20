// Não tratamos pc > tamanho*4
module MEI #(
    parameter TAMANHO = 256 // tamanho da memoria em numeros de palavra
)(
    input wire clk,
    input wire rst,

    input wire [9:0] pc,
    output reg [31:0] saida0, // instrução no endereço pc
    output reg [31:0] saida1, // instrução no endereço pc + 4
    output reg [31:0] saida2, // instrução no endereço pc + 8

    //IVAN FEATURE: PC de cada instrução, registrado junto com ela
    output reg [9:0] pc0, pc1, pc2
);
    reg [31:0] memoria [TAMANHO-1:0]; // largura * profundidade

    always @(posedge clk) begin
        if (rst) begin
            saida0   <= 32'b0;
            saida1   <= 32'b0;
            saida2   <= 32'b0;
            pc0 <= 10'd0; pc1 <= 10'd0; pc2 <= 10'd0;   //IVAN FEATURE
        end else begin
            saida0 <= memoria[pc >> 2];
            saida1 <= memoria[(pc >> 2) + 10'b1];
            saida2 <= memoria[(pc >> 2) + 10'b10];
            pc0 <= pc; pc1 <= pc + 10'd4; pc2 <= pc + 10'd8;   //IVAN FEATURE
        end
    end
endmodule
