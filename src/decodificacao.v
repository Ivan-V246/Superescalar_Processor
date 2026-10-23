// Decodificador de instrucoes RV32I.
// Instrucoes suportadas neste arquivo:
//   - R-type: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
//   - I-type aritmeticas: ADDI, SLLI, SLTI, SLTIU, XORI, SRLI, SRAI, ORI, ANDI
//   - LOAD: LB, LH, LW, LBU, LHU
//   - STORE: SB, SH, SW
// Branches, jumps e demais opcodes nao sao aceitos nesta versao.

module decoder (
    input  wire [31:0] instr,
    output reg         instr_valid,
    output reg  [2:0]  dst,
    output reg  [4:0]  rs1,
    output reg  [4:0]  rs2,
    output reg  [4:0]  rd,
    output reg  [3:0]  alu_op,
    output reg  [2:0]  mem_funct3
);

    // Tipos de destino usados pelo despacho.
    localparam [2:0] DST_REG   = 3'b000;
    localparam [2:0] DST_LOAD  = 3'b010;
    localparam [2:0] DST_STORE = 3'b100;

    // Codigos internos da operacao da ULA.
    localparam [3:0] ALU_ADD  = 4'd0;
    localparam [3:0] ALU_SUB  = 4'd1;
    localparam [3:0] ALU_SLL  = 4'd2;
    localparam [3:0] ALU_SLT  = 4'd3;
    localparam [3:0] ALU_SLTU = 4'd4;
    localparam [3:0] ALU_XOR  = 4'd5;
    localparam [3:0] ALU_SRL  = 4'd6;
    localparam [3:0] ALU_SRA  = 4'd7;
    localparam [3:0] ALU_OR   = 4'd8;
    localparam [3:0] ALU_AND  = 4'd9;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    always @* begin
        // Valores padrao: instrucao invalida ate ser reconhecida.
        instr_valid = 1'b0;
        dst         = DST_REG;
        rs1         = instr[19:15];
        rs2         = instr[24:20];
        rd          = instr[11:7];
        alu_op      = ALU_ADD;
        mem_funct3  = funct3;

        case (opcode)
            // Operacoes aritmeticas/logicas com dois registradores.
            7'b0110011: begin
                case (funct3)

                    3'b000: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_ADD;
                            instr_valid = 1'b1;
                        end else if (funct7 == 7'b0100000) begin
                            alu_op = ALU_SUB;
                            instr_valid = 1'b1;
                        end
                    end

                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SLL;
                            instr_valid = 1'b1;
                        end
                    end

                    3'b010: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SLT;
                            instr_valid = 1'b1;
                        end
                    end

                    3'b011: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SLTU;
                            instr_valid = 1'b1;
                        end
                    end

                    3'b100: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_XOR;
                            instr_valid = 1'b1;
                        end
                    end
                    
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SRL;
                            instr_valid = 1'b1;
                        end else if (funct7 == 7'b0100000) begin
                            alu_op = ALU_SRA;
                            instr_valid = 1'b1;
                        end
                    end

                    3'b110: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_OR;
                            instr_valid = 1'b1;
                        end
                    end

                    3'b111: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_AND;
                            instr_valid = 1'b1;
                        end
                    end

                    default: instr_valid = 1'b0;
                endcase
            end

            // Operacoes aritmeticas/logicas com imediato.
            7'b0010011: begin

                case (funct3)
                    3'b000: begin alu_op = ALU_ADD;  instr_valid = 1'b1; end // ADDI
                    3'b010: begin alu_op = ALU_SLT;  instr_valid = 1'b1; end // SLTI
                    3'b011: begin alu_op = ALU_SLTU; instr_valid = 1'b1; end // SLTIU
                    3'b100: begin alu_op = ALU_XOR;  instr_valid = 1'b1; end // XORI
                    3'b110: begin alu_op = ALU_OR;   instr_valid = 1'b1; end // ORI
                    3'b111: begin alu_op = ALU_AND;  instr_valid = 1'b1; end // ANDI
                    3'b001: begin

                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SLL;
                            instr_valid = 1'b1;
                        end
                    end

                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SRL;
                            instr_valid = 1'b1;
                        end else if (funct7 == 7'b0100000) begin
                            alu_op = ALU_SRA;
                            instr_valid = 1'b1;
                        end
                    end

                    default: instr_valid = 1'b0;

                endcase

                // Em instrucoes I-type, rs2 nao e usado como registrador.
                rs2 = 5'd0;

            end

            // LOAD: LB, LH, LW, LBU, LHU.
            7'b0000011: begin

                case (funct3)
                    3'b000, 3'b001, 3'b010, 3'b100, 3'b101: begin
                        instr_valid = 1'b1;
                        dst = DST_LOAD;
                        rs2 = 5'd0;
                        alu_op = ALU_ADD; // endereco = rs1 + imediato
                    end
                    default: instr_valid = 1'b0;
                endcase

            end

            // STORE: SB, SH, SW.
            7'b0100011: begin

                case (funct3)
                    3'b000, 3'b001, 3'b010: begin
                        instr_valid = 1'b1;
                        dst = DST_STORE;
                        rd = 5'd0; // bits [11:7] pertencem ao imediato
                        alu_op = ALU_ADD; // endereco = rs1 + imediato
                    end
                    default: instr_valid = 1'b0;
                endcase

            end

            default: begin
                instr_valid = 1'b0;
            end

        endcase

        // Nao habilita um destino de registrador para instrucoes invalidas.
        if (!instr_valid) begin

            dst = DST_REG;
            rs1 = 5'd0;
            rs2 = 5'd0;
            rd = 5'd0;
            alu_op = ALU_ADD;
            mem_funct3 = 3'd0;
            
        end
    end

endmodule