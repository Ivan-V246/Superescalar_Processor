
`timescale 1ns/1ps

module tb_decodificacao;

    reg [31:0] instr;

    wire instr_valid;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;
    wire [3:0] alu_op;
    wire [2:0] mem_funct3;

    decoder dut (
        .instr(instr),
        .instr_valid(instr_valid),
        .dst(),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .alu_op(alu_op),
        .mem_funct3(mem_funct3)
    );

    initial begin
        $dumpfile("tb_decodificacao.vcd");
        $dumpvars(0, tb_decodificacao);

        $display("INICIO DOS TESTES DE DECODIFICACAO");

        // Teste 1: ADD x1, x2, x3
        instr = {7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011};
        #10;

        if (instr_valid &&
            rs1 == 5'd2 &&
            rs2 == 5'd3 &&
            rd == 5'd1) begin
            $display("PASSOU: decodificacao de ADD");
        end else begin
            $display("FALHOU: decodificacao de ADD");
            $finish;
        end

        // Teste 2: LW x5, 12(x2)
        instr = {12'd12, 5'd2, 3'b010, 5'd5, 7'b0000011};
        #10;

        if (instr_valid &&
            rs1 == 5'd2 &&
            rd == 5'd5 &&
            mem_funct3 == 3'b010) begin
            $display("PASSOU: decodificacao de LW");
        end else begin
            $display("FALHOU: decodificacao de LW");
            $finish;
        end

        // Teste 3: opcode invalido
        instr = 32'h0000007F;
        #10;

        if (!instr_valid) begin
            $display("PASSOU: rejeicao de instrucao invalida");
        end else begin
            $display("FALHOU: instrucao invalida foi aceita");
            $finish;
        end

        $display("TODOS OS TESTES PASSARAM");
        $finish;
    end

endmodule
