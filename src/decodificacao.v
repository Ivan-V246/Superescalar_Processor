//==============================================================================
// Decodificador RV32I
//
// Combinacional. Recebe uma instrução e devolve os campos que o despacho usa
// para alocar e enviar.
//
// Instruções reconhecidas:
//   - Tipo R:            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
//   - Tipo I aritmético: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
//   - Loads:             LB, LH, LW, LBU, LHU
//   - Stores:            SB, SH, SW
//   - Desvios:           BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR
//   - Tipo U:            LUI, AUIPC
//
// Fim de programa: ECALL, EBREAK e a instrução toda zero (que o RISC-V define
// como ilegal justamente para detectar memória vazia) marcam parada = 1 e saem
// com instr_valid = 0; o despacho para de aceitar a partir dela. Em simulação,
// uma instrução com bits indefinidos (memória não carregada) também é parada.
//
// Qualquer outra instrução (FENCE, CSR ou lixo) é marcada ilegal = 1 e vira
// NOP: segue válida, com rd = rs1 = rs2 = 0 e imediato 0, e a escrita cai em x0.
//==============================================================================

module decoder (
    input  wire [31:0] instr,
    output reg         instr_valid, // 0 só nas instruções de parada (ilegais seguem como NOP)
    output reg         parada,      // ECALL, EBREAK, toda zero ou indefinida
    output reg         ilegal,      // Não reconhecida, virou NOP (0 nas de parada)
    output reg         desvio,      // Branches, JAL e JALR: vão para o caminho de desvio
    output reg  [2:0]  dst,         // Destino: 000 banco, 010 Load, 100 Store
                                    // (branches usam 000 com rd = 0)
    output reg  [4:0]  rs1,         // Registradores lidos; 0 quando o campo não é usado
    output reg  [4:0]  rs2,
    output reg  [4:0]  rd,          // Registrador escrito; 0 quando não escreve
    output reg  [3:0]  alu_op,      // Operação da ULA (ADD em Load/Store e desvios)
    output reg  [2:0]  mem_funct3,  // funct3: tamanho em Load/Store, condição nos branches;
                                    // 0 em JAL, LUI, AUIPC e ilegais
    output reg  [31:0] imm          // Imediato estendido a 32 bits (shamt em SLLI/SRLI/SRAI;
                                    // 20 bits de cima no tipo U; 0 no tipo R e ilegais)
);

    // Tipos de destino usados pelo despacho e pelo ROB.
    localparam [2:0] DST_REG   = 3'b000;
    localparam [2:0] DST_LOAD  = 3'b010;
    localparam [2:0] DST_STORE = 3'b100;

    // Códigos internos da operação da ULA.
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

    // Opcodes.
    localparam [6:0] OP_R      = 7'b0110011;
    localparam [6:0] OP_I      = 7'b0010011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;

    // Campos da instrução.
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    // Imediatos de cada formato, já estendidos com sinal.
    wire [31:0] imm_I = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_S = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_B = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_J = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
    wire [31:0] shamt = {27'd0, instr[24:20]};

    // Operação da ULA pelo funct3 (comum aos tipos R e I).
    // O bit 30 diferencia SUB de ADD (só no tipo R) e SRA de SRL.
    reg [3:0] op_funct3;
    always @* begin
        case (funct3)
            3'b000:  op_funct3 = (opcode == OP_R && instr[30]) ? ALU_SUB : ALU_ADD;
            3'b001:  op_funct3 = ALU_SLL;
            3'b010:  op_funct3 = ALU_SLT;
            3'b011:  op_funct3 = ALU_SLTU;
            3'b100:  op_funct3 = ALU_XOR;
            3'b101:  op_funct3 = instr[30] ? ALU_SRA : ALU_SRL;
            3'b110:  op_funct3 = ALU_OR;
            default: op_funct3 = ALU_AND;
        endcase
    end

    // Reconhecimento: a instrução existe no conjunto suportado?
    reg reconhecida;
    always @* begin
        case (opcode)
            // Tipo R: funct7 = 0000000, ou 0100000 só para SUB e SRA.
            OP_R:      reconhecida = (funct7 == 7'b0000000) ||
                                     (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101));
            // Tipo I: os deslocamentos exigem funct7 válido (0100000 só em SRAI).
            OP_I:      reconhecida = (funct3 == 3'b001) ? (funct7 == 7'b0000000) :
                                     (funct3 == 3'b101) ? (funct7 == 7'b0000000 || funct7 == 7'b0100000) :
                                     1'b1;
            // LB, LH, LW, LBU, LHU.
            OP_LOAD:   reconhecida = (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 ||
                                      funct3 == 3'b100 || funct3 == 3'b101);
            // SB, SH, SW.
            OP_STORE:  reconhecida = (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010);
            // BEQ, BNE, BLT, BGE, BLTU, BGEU (funct3 010 e 011 não existem).
            OP_BRANCH: reconhecida = (funct3 != 3'b010 && funct3 != 3'b011);
            OP_JAL:    reconhecida = 1'b1;
            OP_JALR:   reconhecida = (funct3 == 3'b000);
            OP_LUI, OP_AUIPC: reconhecida = 1'b1;
            default:   reconhecida = 1'b0;
        endcase
    end

    // Fim de programa: ECALL, EBREAK, toda zero ou (só em simulação) indefinida.
    wire eh_parada = (instr == 32'h00000073) || (instr == 32'h00100073) ||
                     (instr == 32'h00000000) || ((^instr) === 1'bx);

    // Saídas.
    always @* begin
        // Valores padrão: campos crus da instrução.
        instr_valid = !eh_parada;
        parada      = eh_parada;
        ilegal      = !reconhecida && !eh_parada;
        desvio      = 1'b0;
        dst         = DST_REG;
        rs1         = instr[19:15];
        rs2         = instr[24:20];
        rd          = instr[11:7];
        alu_op      = ALU_ADD;
        mem_funct3  = funct3;
        imm         = 32'd0;

        if (!reconhecida) begin
            // Parada ou ilegal: campos zerados (a ilegal equivale a ADD x0, x0, x0).
            rs1        = 5'd0;
            rs2        = 5'd0;
            rd         = 5'd0;
            mem_funct3 = 3'd0;
        end else begin
            case (opcode)
                OP_R: begin
                    alu_op = op_funct3;
                end

                OP_I: begin
                    alu_op = op_funct3;
                    rs2    = 5'd0;                       // bits [24:20] são o imediato
                    imm    = (funct3 == 3'b001 || funct3 == 3'b101) ? shamt : imm_I;
                end

                OP_LOAD: begin
                    dst = DST_LOAD;
                    rs2 = 5'd0;
                    imm = imm_I;                         // endereço = rs1 + imm
                end

                OP_STORE: begin
                    dst = DST_STORE;
                    rd  = 5'd0;                          // bits [11:7] são o imediato
                    imm = imm_S;                         // endereço = rs1 + imm, dado = rs2
                end

                OP_BRANCH: begin
                    desvio = 1'b1;
                    rd     = 5'd0;                       // não escreve: a escrita cai em x0
                    imm    = imm_B;                      // alvo = pc + imm
                end

                OP_JAL: begin
                    desvio = 1'b1;
                    rs1    = 5'd0;                       // não lê registradores
                    rs2    = 5'd0;
                    mem_funct3 = 3'd0;                   // bits [14:12] são o imediato
                    imm    = imm_J;                      // alvo = pc + imm, rd = pc + 4
                end

                OP_LUI, OP_AUIPC: begin
                    rs1        = 5'd0;                   // não lê registradores
                    rs2        = 5'd0;
                    mem_funct3 = 3'd0;                   // bits [14:12] são o imediato
                    imm        = {instr[31:12], 12'd0};  // LUI: rd = imm; AUIPC: rd = pc + imm
                end

                default: begin                           // OP_JALR
                    desvio = 1'b1;
                    rs2    = 5'd0;
                    imm    = imm_I;                      // alvo = (rs1 + imm) & ~1, rd = pc + 4
                end
            endcase
        end
    end

endmodule
