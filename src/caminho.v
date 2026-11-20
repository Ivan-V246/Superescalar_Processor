//==============================================================================
// Caminho de execução
//
// Executa as instruções comuns: tipo R, tipo I, LUI, AUIPC, e calcula o
// endereço dos loads e stores.
//
//   - Recebe a instrução com os operandos certos (da unidade de hazard) e o PC.
//   - Calcula o resultado na ULA: o valor de rd, ou o endereço (rs1 + imm)
//     nos loads e stores, que vai ao ROB e aos buffers.
//   - Não escreve no banco nem acessa a memória: isso é feito pelo ROB (commit)
//     e pelos Load/Store Buffers.
//   - Latência de 1 ciclo; aceita uma instrução por ciclo (ready sempre 1).
//==============================================================================

module caminho (
    input  wire        clk, rst,

    //---- Entradas: instrução enviada pelo despacho ----
    input  wire        valido,          // Há instrução neste ciclo
    input  wire [31:0] instr,           // Instrução
    input  wire [31:0] valor_rs1,       // Operando rs1
    input  wire [31:0] valor_rs2,       // Operando rs2 (tipo R)
    input  wire [4:0]  rob_id,          // Posição no ROB
    input  wire [9:0]  pc,              // PC da instrução (usado pelo AUIPC)

    output wire        ready,           // Sinal para receber novas instruções; Atualmente, sempre 1

    //---- Saídas: resultado para o ROB e o hazard (1 ciclo depois) ----
    output reg         wb,              // Instrução terminou
    output reg  [4:0]  rid,             // rob_id dela
    output reg  [31:0] r                // Valor de rd, ou endereço (load/store)
);

    // Campos da instrucao (IF_ID.v)
    wire [6:0]  opcode = instr[6:0];
    wire [2:0]  funct3 = instr[14:12];
    wire [6:0]  funct7 = instr[31:25];

    wire [11:0] imm_I  = instr[31:20];
    wire [11:0] imm_S  = {instr[31:25], instr[11:7]};
    wire [19:0] imm_U  = instr[31:12];

    // Controle (control.v)
    reg [1:0] ula_op, alu_src1, alu_src2;

    always @(*) begin
        case (opcode)
            7'b0110011: begin // tipo R
                ula_op = 2'b10;
                alu_src1 = 2'b00;
                alu_src2 = 2'b00;
            end
            7'b0010011: begin // tipo I
                ula_op = 2'b10;
                alu_src1 = 2'b00;
                alu_src2 = 2'b01;
            end
            7'b0000011: begin // load
                ula_op = 2'b00;
                alu_src1 = 2'b00;
                alu_src2 = 2'b01;
            end
            7'b0100011: begin // store
                ula_op = 2'b00;
                alu_src1 = 2'b00;
                alu_src2 = 2'b01;
            end
            7'b0110111: begin // lui
                ula_op = 2'b00;
                alu_src1 = 2'b10;
                alu_src2 = 2'b01;
            end
            7'b0010111: begin // auipc
                ula_op = 2'b00;
                alu_src1 = 2'b01;
                alu_src2 = 2'b01;
            end
            default: begin
                ula_op = 2'b00;
                alu_src1 = 2'b00;
                alu_src2 = 2'b00;
            end
        endcase
    end

    // Gerador de imediatos (RV32i.v)
    reg [31:0] imm_gen_output;

    always @(*) begin
        case (opcode)
            7'b0110011: imm_gen_output = {32{1'b0}};
            7'b0010011, 7'b0000011: imm_gen_output = {{20{imm_I[11]}}, imm_I};
            7'b0100011: imm_gen_output = {{20{imm_S[11]}}, imm_S};
            7'b0010111, 7'b0110111: imm_gen_output = {imm_U, 12'b0};
            default: imm_gen_output = 32'b0;
        endcase
    end

    // Operandos da ULA
    reg [31:0] ULA_A, ULA_B;

    always @(*) begin
        case (alu_src1)
            2'b00: ULA_A = valor_rs1;
            2'b01: ULA_A = {22'b0, pc};
            2'b10: ULA_A = 32'b0;
            default: ULA_A = valor_rs1;
        endcase

        case (alu_src2)
            2'b00: ULA_B = valor_rs2;
            2'b01: ULA_B = imm_gen_output;
            default: ULA_B = valor_rs2;
        endcase
    end

    // Controle da ULA (Ula_controler.v)
    // AJUSTE 2: no tipo I, funct7 so vale para shifts
    wire [6:0] funct7_ula = (opcode == 7'b0010011 && funct3 != 3'b001 && funct3 != 3'b101)
                            ? 7'b0 : funct7;

    reg [3:0] operation;

    // AJUSTE 3: sem rst
    always @(*) begin
        operation = 4'b0000;
        case (ula_op)
            2'b00: operation = 4'b0000; // add
            2'b10: begin                // decide por funct3/funct7
                case (funct3)
                    3'b000: begin
                        if (funct7_ula == 7'b0100000) begin
                            operation = 4'b0001; // sub
                        end else begin
                            operation = 4'b0000; // add
                        end
                    end

                    3'b100: operation = 4'b0010; // xor
                    3'b110: operation = 4'b0011; // or
                    3'b111: operation = 4'b0100; // and

                    3'b001: begin
                        if (funct7_ula == 7'b0) begin
                            operation = 4'b0101; // sll
                        end
                    end

                    3'b101: begin
                        if (funct7_ula == 7'b0100000) begin
                            operation = 4'b0111; // sra
                        end else begin
                            operation = 4'b0110; // srl
                        end
                    end

                    3'b010: operation = 4'b1000; // slt

                    3'b011: operation = 4'b1001; // sltu
                endcase
            end
            default: operation = 4'b0000;
        endcase
    end

    // ULA (ULA.v)
    reg [31:0] C;

    always @(*) begin
        case (operation)
            4'b0000: C = ULA_A + ULA_B;
            4'b0001: C = ULA_A - ULA_B;
            4'b0010: C = ULA_A ^ ULA_B;
            4'b0011: C = ULA_A | ULA_B;
            4'b0100: C = ULA_A & ULA_B;
            4'b0101: C = ULA_A << ULA_B[4:0];
            4'b0110: C = ULA_A >> ULA_B[4:0];
            4'b0111: C = $signed(ULA_A) >>> ULA_B[4:0]; // AJUSTE 1: so ULA_B[4:0]
            4'b1000: C = ( $signed(ULA_A) < $signed(ULA_B) ) ? 32'b1 : 32'b0;
            4'b1001: C = ( ULA_A < ULA_B ) ? 32'b1 : 32'b0;
            default: C = ULA_A + ULA_B;
        endcase
    end

    assign ready = 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            wb        <= 1'b0;
            rid       <= 5'b0;
            r         <= 32'b0;
        end else begin
            wb        <= valido;
            rid       <= rob_id;
            r         <= C;
        end
    end
endmodule
