`timescale 1ns/1ps

// Testbench do decodificador.
//   Parte 1: casos dirigidos, um por classe de instrucao, com imediatos
//            positivos e negativos, ilegais (viram NOP) e paradas.
//   Parte 2: 20000 instrucoes aleatorias comparadas com um modelo de
//            referencia escrito aqui, de forma independente do DUT.
module tb_decodificacao;

    reg  [31:0] instr;
    wire        instr_valid, parada, ilegal, desvio;
    wire [2:0]  dst, mem_funct3;
    wire [4:0]  rs1, rs2, rd;
    wire [3:0]  alu_op;
    wire [31:0] imm;

    decoder dut (
        .instr(instr), .instr_valid(instr_valid), .parada(parada), .ilegal(ilegal), .desvio(desvio),
        .dst(dst), .rs1(rs1), .rs2(rs2), .rd(rd),
        .alu_op(alu_op), .mem_funct3(mem_funct3), .imm(imm)
    );

    integer erros = 0, testes = 0, i, n_ilegais, n_desvios;

    // ---------------- Montagem das instrucoes ----------------
    function [31:0] R(input [6:0] f7, input [4:0] b, a, input [2:0] f3, input [4:0] d);
        R = {f7, b, a, f3, d, 7'b0110011};
    endfunction
    function [31:0] I(input [6:0] op, input [11:0] im, input [4:0] a, input [2:0] f3, input [4:0] d);
        I = {im, a, f3, d, op};
    endfunction
    function [31:0] S(input [11:0] im, input [4:0] b, a, input [2:0] f3);
        S = {im[11:5], b, a, f3, im[4:0], 7'b0100011};
    endfunction
    function [31:0] B(input [12:0] im, input [4:0] b, a, input [2:0] f3);
        B = {im[12], im[10:5], b, a, f3, im[4:1], im[11], 7'b1100011};
    endfunction
    function [31:0] J(input [20:0] im, input [4:0] d);
        J = {im[20], im[10:1], im[11], im[19:12], d, 7'b1101111};
    endfunction

    // ---------------- Conferencia ----------------
    task confere(input [8*20-1:0] nome,
                 input e_par, e_il, e_desv, input [2:0] e_dst,
                 input [4:0] e_rs1, e_rs2, e_rd,
                 input [3:0] e_op, input [2:0] e_f3, input [31:0] e_imm);
        begin
            #1;
            testes = testes + 1;
            if (instr_valid !== !e_par || parada !== e_par || ilegal !== e_il || desvio !== e_desv || dst !== e_dst ||
                rs1 !== e_rs1 || rs2 !== e_rs2 || rd !== e_rd ||
                alu_op !== e_op || mem_funct3 !== e_f3 || imm !== e_imm) begin
                erros = erros + 1;
                if (erros <= 10) begin
                    $display("FALHOU %0s: instr=%h", nome, instr);
                    $display("  obtido:   v=%b par=%b il=%b desv=%b dst=%b rs1=%0d rs2=%0d rd=%0d op=%0d f3=%b imm=%h",
                             instr_valid, parada, ilegal, desvio, dst, rs1, rs2, rd, alu_op, mem_funct3, imm);
                    $display("  esperado: v=%b par=%b il=%b desv=%b dst=%b rs1=%0d rs2=%0d rd=%0d op=%0d f3=%b imm=%h",
                             !e_par, e_par, e_il, e_desv, e_dst, e_rs1, e_rs2, e_rd, e_op, e_f3, e_imm);
                end
            end
        end
    endtask

    // ---------------- Modelo de referencia ----------------
    // Classifica a instrucao por mnemonico e monta as saidas esperadas.
    reg        m_par, m_il, m_desv;
    reg [2:0]  m_dst, m_f3;
    reg [4:0]  m_rs1, m_rs2, m_rd;
    reg [3:0]  m_op;
    reg [31:0] m_imm;

    task modelo(input [31:0] x);
        reg [6:0] op, f7; reg [2:0] f3; reg [3:0] ula;
        begin
            op = x[6:0]; f3 = x[14:12]; f7 = x[31:25];
            // Operacao da ULA pelo funct3 (tipo R e I)
            case (f3)
                0: ula = 0; 1: ula = 2; 2: ula = 3; 3: ula = 4;
                4: ula = 5; 5: ula = (f7 == 7'h20) ? 7 : 6; 6: ula = 8; 7: ula = 9;
            endcase
            // Padrao: ilegal (NOP), ou parada nas instrucoes de fim de programa
            m_par = (x == 32'h00000073 || x == 32'h00100073 || x == 32'h0);
            m_il = !m_par; m_desv = 0; m_dst = 3'b000; m_rs1 = 0; m_rs2 = 0; m_rd = 0;
            m_op = 0; m_f3 = 0; m_imm = 0;

            if (op == 7'h33 && (f7 == 0 || (f7 == 7'h20 && (f3 == 0 || f3 == 5)))) begin
                m_il = 0; m_rs1 = x[19:15]; m_rs2 = x[24:20]; m_rd = x[11:7]; m_f3 = f3;
                m_op = (f3 == 0 && f7 == 7'h20) ? 1 : ula;
            end else if (op == 7'h13 && (f3 == 0 || f3 == 2 || f3 == 3 || f3 == 4 || f3 == 6 || f3 == 7)) begin
                m_il = 0; m_rs1 = x[19:15]; m_rd = x[11:7]; m_f3 = f3; m_op = ula;
                m_imm = {{20{x[31]}}, x[31:20]};
            end else if (op == 7'h13 && ((f3 == 1 && f7 == 0) || (f3 == 5 && (f7 == 0 || f7 == 7'h20)))) begin
                m_il = 0; m_rs1 = x[19:15]; m_rd = x[11:7]; m_f3 = f3; m_op = ula;
                m_imm = x[24:20];
            end else if (op == 7'h03 && (f3 <= 2 || f3 == 4 || f3 == 5)) begin
                m_il = 0; m_dst = 3'b010; m_rs1 = x[19:15]; m_rd = x[11:7]; m_f3 = f3;
                m_imm = {{20{x[31]}}, x[31:20]};
            end else if (op == 7'h23 && f3 <= 2) begin
                m_il = 0; m_dst = 3'b100; m_rs1 = x[19:15]; m_rs2 = x[24:20]; m_f3 = f3;
                m_imm = {{20{x[31]}}, x[31:25], x[11:7]};
            end else if (op == 7'h63 && f3 != 2 && f3 != 3) begin
                m_il = 0; m_desv = 1; m_rs1 = x[19:15]; m_rs2 = x[24:20]; m_f3 = f3;
                m_imm = {{20{x[31]}}, x[7], x[30:25], x[11:8], 1'b0};
            end else if (op == 7'h6F) begin
                m_il = 0; m_desv = 1; m_rd = x[11:7];
                m_imm = {{12{x[31]}}, x[19:12], x[20], x[30:21], 1'b0};
            end else if (op == 7'h67 && f3 == 0) begin
                m_il = 0; m_desv = 1; m_rs1 = x[19:15]; m_rd = x[11:7]; m_f3 = f3;
                m_imm = {{20{x[31]}}, x[31:20]};
            end
        end
    endtask

    // Gera uma instrucao aleatoria, com opcode valido na maior parte das vezes
    function [31:0] aleatoria(input integer sorteio);
        reg [31:0] x;
        begin
            x = $random;
            case (sorteio % 10)
                0: x[6:0] = 7'h33;
                1: begin x[6:0] = 7'h33; x[31:25] = (x[31]) ? 7'h20 : 7'h00; end
                2: x[6:0] = 7'h13;
                3: begin x[6:0] = 7'h13; x[31:25] = (x[31]) ? 7'h20 : 7'h00; end
                4: x[6:0] = 7'h03;
                5: x[6:0] = 7'h23;
                6: x[6:0] = 7'h63;
                7: x[6:0] = 7'h6F;
                8: x[6:0] = 7'h67;
                default: ;  // totalmente aleatoria (quase sempre ilegal)
            endcase
            aleatoria = x;
        end
    endfunction

    initial begin
        $display("INICIO DOS TESTES DE DECODIFICACAO");

        // ---------------- Parte 1: casos dirigidos ----------------
        //            nome         par il desv dst     rs1 rs2 rd  op f3     imm
        instr = R(7'h00, 3, 2, 3'b000, 1);
          confere("ADD",           0, 0, 0, 3'b000, 2,  3,  1,  0, 3'b000, 0);
        instr = R(7'h20, 3, 2, 3'b000, 1);
          confere("SUB",           0, 0, 0, 3'b000, 2,  3,  1,  1, 3'b000, 0);
        instr = R(7'h20, 7, 6, 3'b101, 5);
          confere("SRA",           0, 0, 0, 3'b000, 6,  7,  5,  7, 3'b101, 0);
        instr = R(7'h00, 9, 8, 3'b111, 4);
          confere("AND",           0, 0, 0, 3'b000, 8,  9,  4,  9, 3'b111, 0);
        instr = I(7'h13, 12'hFFB, 2, 3'b000, 1);
          confere("ADDI -5",       0, 0, 0, 3'b000, 2,  0,  1,  0, 3'b000, 32'hFFFFFFFB);
        instr = I(7'h13, 12'h7FF, 2, 3'b110, 1);
          confere("ORI 2047",      0, 0, 0, 3'b000, 2,  0,  1,  8, 3'b110, 32'h000007FF);
        instr = I(7'h13, {7'h20, 5'd3}, 4, 3'b101, 5);
          confere("SRAI 3",        0, 0, 0, 3'b000, 4,  0,  5,  7, 3'b101, 3);
        instr = I(7'h13, {7'h00, 5'd31}, 4, 3'b001, 5);
          confere("SLLI 31",       0, 0, 0, 3'b000, 4,  0,  5,  2, 3'b001, 31);
        instr = I(7'h03, 12'd12, 2, 3'b010, 5);
          confere("LW 12",         0, 0, 0, 3'b010, 2,  0,  5,  0, 3'b010, 12);
        instr = I(7'h03, 12'hFFC, 2, 3'b100, 5);
          confere("LBU -4",        0, 0, 0, 3'b010, 2,  0,  5,  0, 3'b100, 32'hFFFFFFFC);
        instr = S(12'd40, 7, 3, 3'b010);
          confere("SW 40",         0, 0, 0, 3'b100, 3,  7,  0,  0, 3'b010, 40);
        instr = S(12'h800, 7, 3, 3'b000);
          confere("SB -2048",      0, 0, 0, 3'b100, 3,  7,  0,  0, 3'b000, 32'hFFFFF800);
        instr = B(13'd16, 2, 1, 3'b000);
          confere("BEQ +16",       0, 0, 1, 3'b000, 1,  2,  0,  0, 3'b000, 16);
        instr = B(13'h1FF8, 2, 1, 3'b101);
          confere("BGE -8",        0, 0, 1, 3'b000, 1,  2,  0,  0, 3'b101, 32'hFFFFFFF8);
        instr = B(13'h0FFE, 5, 4, 3'b111);
          confere("BGEU +4094",    0, 0, 1, 3'b000, 4,  5,  0,  0, 3'b111, 4094);
        instr = J(21'd2048, 1);
          confere("JAL +2048",     0, 0, 1, 3'b000, 0,  0,  1,  0, 3'b000, 2048);
        instr = J(21'h1FFFFC, 1);
          confere("JAL -4",        0, 0, 1, 3'b000, 0,  0,  1,  0, 3'b000, 32'hFFFFFFFC);
        instr = I(7'h67, 12'hFFE, 6, 3'b000, 1);
          confere("JALR -2",       0, 0, 1, 3'b000, 6,  0,  1,  0, 3'b000, 32'hFFFFFFFE);
        instr = 32'h123450B7;   // LUI x1, 0x12345
          confere("LUI (ilegal)",  0, 1, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = 32'h00000097;   // AUIPC x1, 0
          confere("AUIPC (ilegal)",0, 1, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = 32'h00000073;   // ECALL
          confere("ECALL (parada)",1, 0, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = R(7'h20, 3, 2, 3'b110, 1);   // OR com funct7 errado
          confere("OR/f7 (ilegal)",0, 1, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = B(13'd16, 2, 1, 3'b010);     // funct3 inexistente em branch
          confere("B/f3 (ilegal)", 0, 1, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = I(7'h67, 12'd0, 6, 3'b001, 1); // JALR com funct3 != 0
          confere("JALR/f3 (ileg)",0, 1, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = 32'h00000000;
          confere("zeros (parada)",1, 0, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);

        instr = 32'h00100073;   // EBREAK
          confere("EBREAK (parada)",1, 0, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = 32'hxxxxxxxx;   // memoria nao carregada
          confere("indefinida",     1, 0, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);
        instr = 32'h00000013;   // NOP canonico (ADDI x0, x0, 0) nao e parada
          confere("NOP (addi)",     0, 0, 0, 3'b000, 0,  0,  0,  0, 3'b000, 0);

        if (erros == 0) $display("PASSOU: %0d casos dirigidos", testes);

        // ---------------- Parte 2: aleatorios ----------------
        n_ilegais = 0; n_desvios = 0;
        for (i = 0; i < 20000; i = i + 1) begin
            instr = aleatoria(i);
            modelo(instr);
            if (m_il) n_ilegais = n_ilegais + 1;
            if (m_desv) n_desvios = n_desvios + 1;
            confere("aleatoria", m_par, m_il, m_desv, m_dst, m_rs1, m_rs2, m_rd, m_op, m_f3, m_imm);
        end
        if (erros == 0)
            $display("PASSOU: 20000 instrucoes aleatorias (%0d ilegais, %0d desvios)", n_ilegais, n_desvios);

        if (erros == 0) $display("TODOS OS TESTES PASSARAM");
        else            $display("%0d ERRO(S) em %0d testes", erros, testes);
        $finish;
    end

endmodule
