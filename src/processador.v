module processador (input clk, input rst);

    // ---- pc e controle da busca ----
    reg  [9:0] pc;
    reg        grupo_valido;
    wire       pc_advence;      // vem do despacho

    always @(posedge clk) begin
        if (rst) begin
            pc           <= 0;
            grupo_valido <= 0;
        end else if (pc_advence) begin
            pc           <= pc + 12;
            grupo_valido <= 0;               // saída da MEI agora é velha
        end else begin
            grupo_valido <= 1;               // a MEI já leu o grupo do pc atual
        end
    end

    wire [63:0] mei_saida0;
    wire [63:0] mei_saida1;
    wire [63:0] mei_saida2;

    MEI mei (
        .clk(clk),
        .rst(rst),
        .pc(pc),
        .saida0(mei_saida0),
        .saida1(mei_saida1),
        .saida2(mei_saida2)
    );

    // ---- fios entre despacho, banco e caminhos ----
    wire        p1_valid, p2_valid;          // despacho → caminho: "tem instrução"
    wire [31:0] p1_instr, p2_instr;          // despacho → caminho: a instrução
    wire [4:0]  p1_rs1, p1_rs2;              // despacho → banco: números dos registradores
    wire [4:0]  p2_rs1, p2_rs2;
    wire [31:0] p1_rs1_val, p1_rs2_val;      // banco → caminho e despacho: valores lidos
    wire [31:0] p2_rs1_val, p2_rs2_val;
    wire        p1_ready, p2_ready;          // caminho → despacho: "estou livre"
    wire [4:0]  rob_id1, rob_id2;            // despacho → caminho: posição no ROB

    // saídas dos caminhos
    wire        wb1, wb2;                    // "terminei"
    wire [4:0]  rid1, rid2;                  // qual rob_id terminou
    wire [31:0] r1, r2;                      // o resultado

    // ---- despacho → ROB: o que foi reservado ----
    wire [2:0] disp_v;                           // quais posições são válidas
    wire [2:0] disp_dst1, disp_dst2, disp_dst3;  // tipo: 000 ALU, 010 load, 100 store
    wire [4:0] disp_rd1,  disp_rd2,  disp_rd3;   // registrador destino

    // ---- ROB → despacho ----
    wire       rob_stop;                         // ROB cheio
    wire [4:0] rob_tail;                         // próxima posição livre

    // ---- commit: ROB → banco ----
    wire [2:0]  commit_dst1, commit_dst2, commit_dst3;
    wire [4:0]  commit_rd1,  commit_rd2,  commit_rd3;
    wire [31:0] commit_r1,   commit_r2,   commit_r3;

    wire [4:0]  rob_id3;
    wire [31:0] disp_dado1, disp_dado2, disp_dado3;
    wire [4:0]  commit_rob_id1, commit_rob_id2, commit_rob_id3;
    wire        sb_mem_req, sb_stop;
    wire [31:0] sb_mem_addr, sb_mem_dado;
    wire [31:0] med_saida;
    wire [2:0]  cv_store;

    wire [4:0]  lrid, lb_rid;
    wire        lready, lb_done, lb_mem_req, lb_stop;
    wire [31:0] laddr;
    wire [31:0] lb_dado1, lb_dado2, lb_dado3;
    reg         lb_mem_done;
    reg  [31:0] lb_mem_data;
    wire [2:0]  cv_load;
    wire        load_grant;
    wire [31:0] wdado1, wdado2, wdado3;

    // ---- despacho ----
    despacho desp (
        .clk(clk),
        .rst(rst),

        // ligações com a busca
        .mei_valid({3{grupo_valido}}),       // o mesmo bit repetido 3 vezes
        .mei_instr0(mei_saida0[31:0]),
        .mei_instr1(mei_saida1[31:0]),
        .mei_instr2(mei_saida2[31:0]),
        .mei_ordem0(mei_saida0[63:32]),
        .mei_ordem1(mei_saida1[63:32]),
        .mei_ordem2(mei_saida2[63:32]),
        .mei_stop(),
        .pc_advence(pc_advence),
        .ocupacao(),

        .stop(rob_stop),
        .Rob_tail(rob_tail),
        .load_buffer_stop(lb_stop),
        .store_buffer_stop(sb_stop),
        .v(disp_v),
        .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .rd1(disp_rd1),   .rd2(disp_rd2),   .rd3(disp_rd3),
        .dado1(disp_dado1), .dado2(disp_dado2), .dado3(disp_dado3),

        .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),

        .path1_ready(p1_ready),        .path2_ready(p2_ready),
        .path1_valid(p1_valid),        .path2_valid(p2_valid),
        .path1_instr(p1_instr),        .path2_instr(p2_instr),
        .path1_ordem(),                .path2_ordem(),
        .path1_rs1_addr(p1_rs1),       .path1_rs2_addr(p1_rs2),
        .path2_rs1_addr(p2_rs1),       .path2_rs2_addr(p2_rs2),
        .path1_rs1_data(p1_rs1_val),   .path1_rs2_data(p1_rs2_val),
        .path2_rs1_data(p2_rs1_val),   .path2_rs2_data(p2_rs2_val)
    );

    // ---- decide quais commits escrevem no banco ----
    wire [2:0] we_banco;
    assign cv_load[0] = (commit_dst1 == 3'b010);
    assign cv_load[1] = (commit_dst2 == 3'b010);
    assign cv_load[2] = (commit_dst3 == 3'b010);

    assign we_banco[0] = (commit_dst1 == 3'b000) | cv_load[0];
    assign we_banco[1] = (commit_dst2 == 3'b000) | cv_load[1];
    assign we_banco[2] = (commit_dst3 == 3'b000) | cv_load[2];

    assign wdado1 = cv_load[0] ? lb_dado1 : commit_r1;
    assign wdado2 = cv_load[1] ? (cv_load[0] ? lb_dado2 : lb_dado1) : commit_r2;
    assign wdado3 = cv_load[2] ? ((cv_load[0] & cv_load[1]) ? lb_dado3 :
                                  (cv_load[0] | cv_load[1]) ? lb_dado2 : lb_dado1) : commit_r3;

    assign cv_store[0] = (commit_dst1 == 3'b100);
    assign cv_store[1] = (commit_dst2 == 3'b100);
    assign cv_store[2] = (commit_dst3 == 3'b100);

    // ---- banco de registradores ----
    banco_registradores banco (
        .clk(clk), .rst(rst),

        // leitura: os números vêm do despacho, os valores vão para os caminhos
        .rs1_1(p1_rs1),     .rs2_1(p1_rs2),
        .rs1_2(p2_rs1),     .rs2_2(p2_rs2),
        .rs1_3(5'd0),       .rs2_3(5'd0),                            // 3ª porta não usada
        .valor_rs1_1(p1_rs1_val), .valor_rs2_1(p1_rs2_val),
        .valor_rs1_2(p2_rs1_val), .valor_rs2_2(p2_rs2_val),
        .valor_rs1_3(),           .valor_rs2_3(),

        .we(we_banco),
        .rd1(commit_rd1),   .rd2(commit_rd2),   .rd3(commit_rd3),
        .dado1(wdado1),     .dado2(wdado2),     .dado3(wdado3)
    );

    // ---- caminhos de execução ----
    caminho caminho1 (
        .clk(clk), .rst(rst),
        .valido(p1_valid),
        .instr(p1_instr),
        .valor_rs1(p1_rs1_val), .valor_rs2(p1_rs2_val),
        .rob_id(rob_id1),
        .ready(p1_ready),
        .wb(wb1), .rid(rid1), .r(r1)
    );

    caminho caminho2 (
        .clk(clk), .rst(rst),
        .valido(p2_valid),
        .instr(p2_instr),
        .valor_rs1(p2_rs1_val), .valor_rs2(p2_rs2_val),
        .rob_id(rob_id2),
        .ready(p2_ready),
        .wb(wb2), .rid(rid2), .r(r2)
    );

    // ---- ROB ----
    rob rob_u (
        .clk(clk), .rst(rst),

        // reserva, vinda do despacho
        .v(disp_v),
        .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .rd1(disp_rd1),   .rd2(disp_rd2),   .rd3(disp_rd3),

        // resultados, vindos dos caminhos
        .wb({1'b0, wb2, wb1}),
        .rid1(rid1), .rid2(rid2), .rid3(5'd0),
        .r1(r1),     .r2(r2),     .r3(32'd0),

        // commit, para o banco
        .cdst1(commit_dst1), .cdst2(commit_dst2), .cdst3(commit_dst3),
        .crid1(commit_rd1),  .crid2(commit_rd2),  .crid3(commit_rd3),
        .cr1(commit_r1),     .cr2(commit_r2),     .cr3(commit_r3),
        .crob_id1(commit_rob_id1), .crob_id2(commit_rob_id2), .crob_id3(commit_rob_id3),

        // loads e stores
        .lrid(lrid), .lready(lready), .laddr(laddr),
        .srid(5'd0), .saddr(),                   // o store buffer guarda o próprio endereço
        .lb_done(lb_done), .lb_rid(lb_rid),

        // para o despacho
        .stop(rob_stop),
        .rob_tail(rob_tail)
    );

    store_buffer sbuf (
        .clk(clk), .rst(rst),
        .v(disp_v),
        .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .dado1(disp_dado1), .dado2(disp_dado2), .dado3(disp_dado3),
        .cv(cv_store),
        .cr1(commit_r1), .cr2(commit_r2), .cr3(commit_r3),
        .mem_req(sb_mem_req), .mem_addr(sb_mem_addr), .mem_dado(sb_mem_dado),
        .stop(sb_stop)
    );

    load_buffer lbuf (
        .clk(clk), .rst(rst),
        .v(disp_v),
        .dst1(disp_dst1), .dst2(disp_dst2), .dst3(disp_dst3),
        .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
        .lrid(lrid), .lready(lready),
        .mem_req(lb_mem_req), .mem_data(lb_mem_data), .mem_done(lb_mem_done),
        .lb_done(lb_done), .lb_rid(lb_rid),
        .cv(cv_load),
        .crob_id1(commit_rob_id1), .crob_id2(commit_rob_id2), .crob_id3(commit_rob_id3),
        .lb_dado1(lb_dado1), .lb_dado2(lb_dado2), .lb_dado3(lb_dado3),
        .stop(lb_stop)
    );

    assign load_grant = lb_mem_req & !sb_mem_req;

    MED med (
        .clk(clk), .rst(rst),
        .memRead(load_grant),
        .memWrite(sb_mem_req),
        .funct3(3'b010),
        .ende_dado(sb_mem_req ? sb_mem_addr : laddr),
        .dado_entrada(sb_mem_dado),
        .dado_saida(med_saida)
    );

    always @(posedge clk) begin
        if (rst) begin
            lb_mem_done <= 1'b0;
            lb_mem_data <= 32'd0;
        end else begin
            lb_mem_done <= load_grant;
            if (load_grant) lb_mem_data <= med_saida;
        end
    end

endmodule