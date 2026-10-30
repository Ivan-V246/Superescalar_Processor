// Caminho de desvio: resolve JAL, JALR e BEQ..BGEU
module caminho_desvio (
    input  wire        clk, rst,

    // Despacho
    input  wire        valido,
    input  wire [31:0] instr,
    input  wire [9:0]  pc,
    input  wire [31:0] valor_rs1,
    input  wire [31:0] valor_rs2,
    input  wire [4:0]  rob_id,
    output wire        ready,

    // ROB
    output reg         wb,
    output reg  [4:0]  rid,
    output reg  [31:0] r,           // pc + 4 (jal/jalr)

    // Busca e despacho
    output reg         resolvido,   // instrucao resolvida
    output reg         tomado,      // fluxo muda
    output reg  [9:0]  alvo         // proximo pc
);
    // Campos da instrucao
    wire [6:0]  opcode = instr[6:0];
    wire [2:0]  funct3 = instr[14:12];
    wire [11:0] imm_I  = instr[31:20];
    wire [11:0] imm_B  = {instr[31], instr[7], instr[30:25], instr[11:8]};
    wire [19:0] imm_J  = {instr[31], instr[19:12], instr[20], instr[30:21]};

    // Tipo
    wire eh_jal    = (opcode == 7'b1101111);
    wire eh_jalr   = (opcode == 7'b1100111);
    wire eh_branch = (opcode == 7'b1100011);

    // Imediatos
    wire [31:0] imm_i32 = {{20{imm_I[11]}}, imm_I};
    wire [31:0] imm_b32 = {{19{imm_B[11]}}, imm_B, 1'b0};
    wire [31:0] imm_j32 = {{11{imm_J[19]}}, imm_J, 1'b0};

    // Branch decider
    reg cond;

    always @(*) begin
        cond = 1'b0;
        if (eh_branch) begin
            case (funct3)
                3'b000: cond = ($signed(valor_rs1) == $signed(valor_rs2)); // beq
                3'b001: cond = ($signed(valor_rs1) != $signed(valor_rs2)); // bne
                3'b100: cond = ($signed(valor_rs1) <  $signed(valor_rs2)); // blt
                3'b101: cond = ($signed(valor_rs1) >= $signed(valor_rs2)); // bge
                3'b110: cond = (valor_rs1 <  valor_rs2);                   // bltu
                3'b111: cond = (valor_rs1 >= valor_rs2);                   // bgeu
                default: cond = 1'b0;
            endcase
        end
    end

    // Enderecos
    wire [31:0] pc32      = {22'b0, pc};
    wire [31:0] pc_mais_4 = pc32 + 32'd4;
    wire [31:0] alvo_jalr = (valor_rs1 + imm_i32) & ~32'd1;
    wire [31:0] alvo_jal  = pc32 + imm_j32;
    wire [31:0] alvo_br   = pc32 + imm_b32;

    // Proximo pc
    wire        muda = eh_jal | eh_jalr | (eh_branch & cond);
    wire [31:0] prox = eh_jalr ? alvo_jalr :
                       eh_jal  ? alvo_jal  :
                       muda    ? alvo_br   : pc_mais_4;

    assign ready = 1'b1;

    // Saida (1 ciclo)
    always @(posedge clk) begin
        if (rst) begin
            wb        <= 1'b0;
            rid       <= 5'b0;
            r         <= 32'b0;
            resolvido <= 1'b0;
            tomado    <= 1'b0;
            alvo      <= 10'b0;
        end else begin
            wb        <= valido;
            rid       <= rob_id;
            r         <= (eh_jal | eh_jalr) ? pc_mais_4 : 32'b0;
            resolvido <= valido;
            tomado    <= valido & muda;
            alvo      <= prox[9:0];
        end
    end
endmodule
