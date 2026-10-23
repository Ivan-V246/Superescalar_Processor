// Caminho de execucao: resolve uma instrucao e entrega o resultado ao ROB
module caminho (
    input  wire        clk, rst,

    // Despacho
    input  wire        valido,
    input  wire [31:0] instr,
    input  wire [31:0] valor_rs1,
    input  wire [31:0] valor_rs2,
    input  wire [4:0]  rob_id,
    output wire        ready,

    // ROB
    output reg         wb,
    output reg  [4:0]  rid,
    output reg  [31:0] r            // valor de rd ou endereco (load/store)
);
    // Campos da instrucao (IF_ID.v)
    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rd     = instr[11:7];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [2:0]  funct3 = instr[14:12];
    wire [6:0]  funct7 = instr[31:25];

    wire [11:0] imm_I  = instr[31:20];
    wire [11:0] imm_S  = {instr[31:25], instr[11:7]};
    wire [11:0] imm_B  = {instr[31], instr[7], instr[30:25], instr[11:8]};
    wire [19:0] imm_U  = instr[31:12];
    wire [19:0] imm_J  = {instr[31], instr[19:12], instr[20], instr[30:21]};

    // Controle (control.v)
    reg mem_rd, mem_wr, reg_wr, mux_reg_wr, branch, jump, jalr;
    reg [1:0] ula_op, alu_src1, alu_src2;

    always @(*) begin
        case (opcode)
            7'b0110011: begin // tipo R
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b10;
                reg_wr = 1'b1;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b0;
                alu_src2 = 2'b0;
                jump = 1'b0;
                jalr = 1'b0;
            end
            7'b0010011: begin // tipo I
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b10;
                reg_wr = 1'b1;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b00;
                alu_src2 = 2'b01;
                jump = 1'b0;
                jalr = 1'b0;
            end
            7'b0000011: begin // load
                branch = 1'b0;
                mem_rd = 1'b1;
                mem_wr = 1'b0;
                ula_op = 2'b00;
                reg_wr = 1'b1;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b00;
                alu_src2 = 2'b01;
                jump = 1'b0;
                jalr = 1'b0;
            end
            7'b0100011: begin // store
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b1;
                ula_op = 2'b00;
                reg_wr = 1'b0;
                mux_reg_wr = 1'b1;
                alu_src1 = 2'b00;
                alu_src2 = 2'b01;
                jump = 1'b0;
                jalr = 1'b0;
            end
            7'b1100011: begin // branch
                branch = 1'b1;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b00;
                reg_wr = 1'b0;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b00;
                alu_src2 = 2'b00;
                jump = 1'b0;
                jalr = 1'b0;
            end
            7'b0110111: begin // lui
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b00;
                reg_wr = 1'b1;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b10;
                alu_src2 = 2'b01;
                jump = 1'b0;
                jalr = 1'b0;
            end
            7'b0010111: begin // auipc
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b00;
                reg_wr = 1'b1;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b01;
                alu_src2 = 2'b01;
                jump = 1'b0;
                jalr = 1'b0;
            end
            7'b1101111: begin // jal
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b00;
                reg_wr = 1'b1;
                mux_reg_wr = 1'b0;
                jump = 1'b1;
                jalr = 1'b0;
                alu_src1 = 2'b01;
                alu_src2 = 2'b10;
            end
            7'b1100111: begin // jalr
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b00;
                reg_wr = 1'b1;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b01;
                alu_src2 = 2'b10;
                jump = 1'b1;
                jalr = 1'b1;
            end
            default: begin
                branch = 1'b0;
                mem_rd = 1'b0;
                mem_wr = 1'b0;
                ula_op = 2'b00;
                reg_wr = 1'b0;
                mux_reg_wr = 1'b0;
                alu_src1 = 2'b00;
                alu_src2 = 2'b00;
                jump = 1'b0;
                jalr = 1'b0;
            end
        endcase
    end

    // Gerador de imediatos (RV32i.v)
    reg [31:0] imm_gen_output;

    always @(*) begin
        case (opcode)
            7'b0110011: imm_gen_output = {32{1'b0}};
            7'b0010011, 7'b0000011, 7'b1100111: imm_gen_output = {{20{imm_I[11]}}, imm_I};
            7'b0100011: imm_gen_output = {{20{imm_S[11]}}, imm_S};
            7'b1100011: imm_gen_output = {{19{imm_B[11]}}, imm_B, 1'b0};
            7'b1101111: imm_gen_output = {{11{imm_J[19]}}, imm_J, 1'b0};
            7'b0010111, 7'b0110111: imm_gen_output = {imm_U, 12'b0};
            default: imm_gen_output = 32'b0;
        endcase
    end

    // Operandos da ULA (sem pc: alu_src1 = 01 vira zero)
    reg [31:0] ULA_A, ULA_B;

    always @(*) begin
        case (alu_src1)
            2'b00: ULA_A = valor_rs1;
            2'b01: ULA_A = 32'b0;
            2'b10: ULA_A = 32'b0;
            default: ULA_A = valor_rs1;
        endcase

        case (alu_src2)
            2'b00: ULA_B = valor_rs2;
            2'b01: ULA_B = imm_gen_output;
            2'b10: ULA_B = 32'd4;
            default: ULA_B = valor_rs2;
        endcase
    end

    // Controle da ULA (Ula_controler.v)
    // AJUSTE 2: no tipo I, funct7 so vale para shifts
    wire [6:0] funct7_ula = (opcode == 7'b0010011 && funct3 != 3'b001 && funct3 != 3'b101)
                            ? 7'b0 : funct7;

    reg [3:0] operation;
    reg err;

    // AJUSTE 3: sem rst
    always @(*) begin
        operation <= 4'b0000;
        err <= 1'b0;
        case (ula_op)
            2'b00: operation <= 4'b0000; // add
            2'b01: operation <= 4'b0001; // sub
            2'b10: begin                 // decide por funct3/funct7
                case (funct3)
                    3'b000: begin
                        if (funct7_ula == 7'b0100000) begin
                            operation <= 4'b0001; // sub
                        end else begin
                            operation <= 4'b0000; // add
                        end
                    end

                    3'b100: operation <= 4'b0010; // xor
                    3'b110: operation <= 4'b0011; // or
                    3'b111: operation <= 4'b0100; // and

                    3'b001: begin
                        if (funct7_ula == 7'b0) begin
                            operation <= 4'b0101; // sll
                            err <= 1'b0;
                        end else begin
                            err <= 1'b1;
                        end
                    end

                    3'b101: begin
                        if (funct7_ula == 7'b0100000) begin
                            operation <= 4'b0111; // sra
                        end else begin
                            operation <= 4'b0110; // srl
                        end
                    end

                    3'b010: operation <= 4'b1000; // slt

                    3'b011: operation <= 4'b1001; // sltu
                endcase
            end
            default: operation <= 4'b0000;
        endcase
    end

    // ULA (ULA.v)
    reg [31:0] C;
    reg ULA_zero;

    always @(*) begin
        case (operation)
            4'b0000: C <= ULA_A + ULA_B;
            4'b0001: C <= ULA_A - ULA_B;
            4'b0010: C <= ULA_A ^ ULA_B;
            4'b0011: C <= ULA_A | ULA_B;
            4'b0100: C <= ULA_A & ULA_B;
            4'b0101: C <= ULA_A << ULA_B[4:0];
            4'b0110: C <= ULA_A >> ULA_B[4:0];
            4'b0111: C <= $signed(ULA_A) >>> ULA_B[4:0]; // AJUSTE 1: so ULA_B[4:0]
            4'b1000: C <= ( $signed(ULA_A) < $signed(ULA_B) ) ? 32'b1 : 32'b0;
            4'b1001: C <= ( ULA_A < ULA_B ) ? 32'b1 : 32'b0;
            default: C <= ULA_A + ULA_B;
        endcase
        if (C == 0) begin
            ULA_zero = 1;
        end else begin
            ULA_zero = 0;
        end
    end

    // Resolucao para o ROB (1 ciclo apos o envio)
    assign ready = 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            wb  <= 1'b0;
            rid <= 5'b0;
            r   <= 32'b0;
        end else begin
            wb  <= valido;
            rid <= rob_id;
            r   <= C;
        end
    end
endmodule
