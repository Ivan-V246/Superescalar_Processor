module despacho(
    input wire clk, rst,

    //Instruções enviadas pelo MEI
    input  wire [2:0]  mei_valid, //Se a instrução enviada é valida

    input  wire [31:0] mei_instr0, mei_instr1, mei_instr2, //O código de cada instruçao
    input  wire [31:0] mei_ordem0, mei_ordem1, mei_ordem2, //A ordem de cada instrução

    output wire  mei_stop,          //Sinal para parar o envio de instruções do MEI para o Despacho

    output reg  pc_advence,       //Avança o PC após a verificação da validade das instruções
    output wire ocupacao,          //Contagem da ocupação do despacho

    //Buffers load e store
    input  wire        load_buffer_stop,
    input  wire        store_buffer_stop,
    output reg  [4:0]  rob_id1, rob_id2, rob_id3,
    output reg  [31:0] dado1, dado2, dado3,

    //Sinais relacionados com o ROB
    input wire stop,              //Enviado pelo ROB para parar de enviar instruções
    input wire [4:0] Rob_tail,

    output reg  [2:0]  v,
    output reg  [2:0]  dst1, dst2, dst3,  //O tipo de destino de cada instrução
    output reg  [4:0]  rd1, rd2, rd3,     //O registrador destino da instrução (5bits)

    //Caminhos externos
    input  wire        path1_ready, //Caminhos prontos para receberem as instruções
    input  wire        path2_ready,
    output reg         path1_valid, //Indica se o caminho esta enviando algo valido
    output reg         path2_valid,
    output reg  [31:0] path1_instr, //Instruçao enviada
    output reg  [31:0] path2_instr,
    output reg  [31:0] path1_ordem,//O numero da ordem da instruçao enviada
    output reg  [31:0] path2_ordem,
    output reg  [4:0]  path1_rs1_addr,//Endereço dos registradores
    output reg  [4:0]  path1_rs2_addr,
    output reg  [4:0]  path2_rs1_addr,
    output reg  [4:0]  path2_rs2_addr,
    input  wire [31:0] path1_rs1_data,//Valores lidos nos registradores
    input  wire [31:0] path1_rs2_data,
    input  wire [31:0] path2_rs1_data,
    input  wire [31:0] path2_rs2_data,

    //IVAN FEATURE: Adicionando PC para controle de Fluxo
    input wire [9:0] mei_pc0, mei_pc1, mei_pc2,

    output reg [9:0] path1_pc, path2_pc,

    //IVAN FEATURE: Previsão de desvio vinda da busca
    input  wire       mei_previu0, mei_previu1, mei_previu2,
    input  wire [9:0] mei_alvo0, mei_alvo1, mei_alvo2,

    output reg        path1_previu, path2_previu,
    output reg  [9:0] path1_alvo, path2_alvo,

    //IVAN FEATURE: Alocação na entrada da fila
    //v, dst, rd e rob_id1..3 passam a ser a alocação de quem entra na fila
    input  wire [4:0] sb_tail, lb_tail,         //Tail dos buffers, para o ponto de corte dos desvios

    output reg  [4:0] path1_rob_id, path2_rob_id,  //rob_id reservado na alocação
    output reg  [4:0] path1_sb_tail, path2_sb_tail, //Ponto de corte do Store Buffer
    output reg  [4:0] path1_lb_tail, path2_lb_tail, //Ponto de corte do Load Buffer

    //IVAN FEATURE: Dado do Store enviado no despacho (dado1..3 deixam de ser usados)
    output reg        store1_valid, store2_valid,
    output reg  [4:0] store1_rob_id, store2_rob_id,
    output reg [31:0] store1_dado, store2_dado,

    //Hazard: o despacho informa as duas instruções da frente e recebe se pode enviá-las
    output wire [4:0] h_rs1_0, h_rs2_0, h_rs1_1, h_rs2_1,  //registradores que cada uma lê
    output wire [4:0] h_rd0, h_rd1,                        //registrador que cada uma escreve
    output wire       h_escreve0, h_escreve1,              //1 se escreve em registrador (ALU ou load)
    output wire       h_alu0, h_alu1,                      //1 se é de ALU (o resultado sai do caminho)
    input  wire       hazard0, hazard1                     //1 = não pode enviar ainda

);
    //Renomeação do sinal enviado pelo ROB
    wire rob_stop = stop;

    //Determinam o destino da instruçao
    localparam [2:0] DST_REG   = 3'b000;
    localparam [2:0] DST_LOAD  = 3'b010;
    localparam [2:0] DST_STORE = 3'b100;

    //Armazenamento do despacho
    //IVAN FEATURE: Layout da entrada
    // [99:95] lb_tail  [94:90] sb_tail  [89:80] alvo  [79] previu
    // [78:74] rob_id   [73:64] pc       [63:32] ordem [31:0] instr
    reg [99:0] buffer [0:15];
    reg [3:0] head, tail;
    reg [4:0] count;

    //Instruções válidas recebidas e despachadas  
    reg [2:0] n_in;
    reg [1:0] n_out;
    reg [4:0] free_slots;
    reg accept_in; //Se novas intruções podem entrar
    
    //
    reg [1:0] write_count;
    integer i;

    wire [31:0] instr0, instr1; //Guarda as duas ultimas instruçoes
    wire [31:0] ordem0, ordem1;

    //IVAN FEATURE:
    wire [9:0] pc0, pc1;

    //IVAN FEATURE: Campos guardados na alocação
    wire [4:0] rob0, rob1;
    wire       previu0, previu1;
    wire [9:0] alvo0, alvo1;
    wire [4:0] sbt0, sbt1, lbt0, lbt1;

    //IVAN FEATURE: Decodificação de quem entra na fila (alocação)
    wire [2:0] ent_dst0, ent_dst1, ent_dst2;
    wire [4:0] ent_rd0, ent_rd1, ent_rd2;
    reg        ent_load, ent_store;  //Algum Load/Store chegando
    reg [1:0]  k_aloc;               //Slot de alocação (compactado)
    reg [2:0]  aloc_dst;
    reg [4:0]  aloc_rd;
    reg [4:0]  sb_corte, lb_corte;   //Ponto de corte de cada entrada
    reg [2:0]  gravado_dst;
    integer j;

    wire dec_valid0, dec_valid1;
    wire [2:0] dec_dst0, dec_dst1;
    wire [4:0] dec_rs1_0, dec_rs2_0, dec_rd0;
    wire [4:0] dec_rs1_1, dec_rs2_1, dec_rd1;
    wire [3:0] dec_alu_op0, dec_alu_op1;
    wire [2:0] dec_mem_funct3_0, dec_mem_funct3_1;

    reg can_send0, can_send1;

    //Ocupaçao da FIFO e regra do bloqueio caso tenha 14 ou mais instruções
    assign ocupacao = count;
    assign mei_stop = (count >= 5'd14);

    assign instr0 = (count >= 5'd1) ? buffer[head][31:0] : 32'd0;
    assign ordem0 = (count >= 5'd1) ? buffer[head][63:32] : 32'd0;
    
    //IVAN FEATURE: PC a ser exposto
    assign pc0 = (count >= 5'd1) ? buffer[head][73:64] : 10'd0;

    assign instr1 = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][31:0] : 32'd0;
    assign ordem1 = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][63:32] : 32'd0;

    //IVAN FEATURE: PC a ser exposto
    assign pc1 = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][73:64] : 10'd0;

    //IVAN FEATURE: Campos da alocação a serem expostos
    assign rob0    = (count >= 5'd1) ? buffer[head][78:74] : 5'd0;
    assign previu0 = (count >= 5'd1) ? buffer[head][79]    : 1'b0;
    assign alvo0   = (count >= 5'd1) ? buffer[head][89:80] : 10'd0;
    assign sbt0    = (count >= 5'd1) ? buffer[head][94:90] : 5'd0;
    assign lbt0    = (count >= 5'd1) ? buffer[head][99:95] : 5'd0;

    assign rob1    = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][78:74] : 5'd0;
    assign previu1 = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][79]    : 1'b0;
    assign alvo1   = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][89:80] : 10'd0;
    assign sbt1    = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][94:90] : 5'd0;
    assign lbt1    = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][99:95] : 5'd0;

    //IVAN FEATURE: Decodificação na entrada da fila (só destino e rd)
    decoder decE0 (.instr(mei_instr0),.instr_valid(),.dst(ent_dst0),.rs1(),.rs2(),
        .rd(ent_rd0),.alu_op(),.mem_funct3());
    decoder decE1 (.instr(mei_instr1),.instr_valid(),.dst(ent_dst1),.rs1(),.rs2(),
        .rd(ent_rd1),.alu_op(),.mem_funct3());
    decoder decE2 (.instr(mei_instr2),.instr_valid(),.dst(ent_dst2),.rs1(),.rs2(),
        .rd(ent_rd2),.alu_op(),.mem_funct3());

    //Instruções da frente para o hazard_forwarding (a decodificação já existia, só expõe)
    assign h_rs1_0 = dec_rs1_0;  assign h_rs2_0 = dec_rs2_0;  assign h_rd0 = dec_rd0;
    assign h_rs1_1 = dec_rs1_1;  assign h_rs2_1 = dec_rs2_1;  assign h_rd1 = dec_rd1;
    assign h_escreve0 = dec_valid0 && (dec_dst0 == DST_REG || dec_dst0 == DST_LOAD);
    assign h_escreve1 = dec_valid1 && (dec_dst1 == DST_REG || dec_dst1 == DST_LOAD);
    assign h_alu0 = (dec_dst0 == DST_REG);
    assign h_alu1 = (dec_dst1 == DST_REG);

    //Decodificação das instruções mais antigas
    decoder dec0 (.instr(instr0),.instr_valid(dec_valid0),.dst(dec_dst0),.rs1(dec_rs1_0),.rs2(dec_rs2_0),
        .rd(dec_rd0),.alu_op(dec_alu_op0),.mem_funct3(dec_mem_funct3_0));
    decoder dec1 (.instr(instr1),.instr_valid(dec_valid1),.dst(dec_dst1),.rs1(dec_rs1_1),.rs2(dec_rs2_1),
        .rd(dec_rd1),.alu_op(dec_alu_op1),.mem_funct3(dec_mem_funct3_1));

   always @* begin
        ////Verifica se as intruções estão válidas
        n_in = {2'b00, mei_valid[0]} + {2'b00, mei_valid[1]}+ {2'b00, mei_valid[2]};

        //Verifica o espaço livre
        free_slots = 5'd0;
        if (count <= 5'd16)
            free_slots = 5'd16 - count;

        //IVAN FEATURE: Algum Load/Store no grupo que está chegando
        ent_load  = (mei_valid[0] && ent_dst0 == DST_LOAD)  || (mei_valid[1] && ent_dst1 == DST_LOAD)  ||
                    (mei_valid[2] && ent_dst2 == DST_LOAD);
        ent_store = (mei_valid[0] && ent_dst0 == DST_STORE) || (mei_valid[1] && ent_dst1 == DST_STORE) ||
                    (mei_valid[2] && ent_dst2 == DST_STORE);

        //IVAN FEATURE: Os bloqueios do ROB e dos buffers passam do envio para a entrada
        accept_in = !mei_stop && (n_in <= free_slots) && !rob_stop &&
                    !(ent_load && load_buffer_stop) && !(ent_store && store_buffer_stop);
        pc_advence = accept_in && (n_in != 0);

        //Inicializa
        v = 3'b000;

        dst1 = DST_REG; dst2 = DST_REG; dst3 = DST_REG;
        rd1 = 5'd0; rd2 = 5'd0; rd3 = 5'd0;
        rob_id1 = Rob_tail; rob_id2 = Rob_tail + 5'd1; rob_id3 = Rob_tail + 5'd2;
        dado1 = 32'd0; dado2 = 32'd0; dado3 = 32'd0;

        path1_valid = 1'b0; path2_valid = 1'b0;
        path1_instr = 32'd0;path2_instr = 32'd0;
        path1_ordem = 32'd0;path2_ordem = 32'd0;
        path1_rs1_addr = 5'd0;path1_rs2_addr = 5'd0;
        path2_rs1_addr = 5'd0;path2_rs2_addr = 5'd0;

        //IVAN FEATURE
        path1_pc = 10'd0; path2_pc = 10'd0;

        //IVAN FEATURE
        path1_previu = 1'b0;   path2_previu = 1'b0;
        path1_alvo = 10'd0;    path2_alvo = 10'd0;
        path1_rob_id = 5'd0;   path2_rob_id = 5'd0;
        path1_sb_tail = 5'd0;  path2_sb_tail = 5'd0;
        path1_lb_tail = 5'd0;  path2_lb_tail = 5'd0;
        store1_valid = 1'b0;   store2_valid = 1'b0;
        store1_rob_id = 5'd0;  store2_rob_id = 5'd0;
        store1_dado = 32'd0;   store2_dado = 32'd0;

        //IVAN FEATURE: Alocação em ordem de quem entra na fila, compactada nos slots
        //(o k-ésimo válido usa o slot k e o rob_id Rob_tail + k)
        k_aloc = 2'd0;
        aloc_dst = DST_REG; aloc_rd = 5'd0;
        if (accept_in) begin
            for (j = 0; j < 3; j = j + 1) begin
                if (mei_valid[j]) begin
                    case (j)
                        0: begin aloc_dst = ent_dst0; aloc_rd = ent_rd0; end
                        1: begin aloc_dst = ent_dst1; aloc_rd = ent_rd1; end
                        2: begin aloc_dst = ent_dst2; aloc_rd = ent_rd2; end
                    endcase
                    case (k_aloc)
                        0: begin v[0] = 1'b1; dst1 = aloc_dst; rd1 = aloc_rd; end
                        1: begin v[1] = 1'b1; dst2 = aloc_dst; rd2 = aloc_rd; end
                        2: begin v[2] = 1'b1; dst3 = aloc_dst; rd3 = aloc_rd; end
                    endcase
                    k_aloc = k_aloc + 2'd1;
                end
            end
        end

        n_out = 2'd0;
        can_send0 = 1'b0;
        can_send1 = 1'b0;

        //Confere se as instruçoes respeitam os bloqueios
        //IVAN FEATURE: Sem bloqueio por ROB/buffers aqui: a instrução já foi alocada.
        //Bloquear o envio por ROB cheio travaria o processador (ROB cheio de quem espera o envio)
        //!hazard0 / !hazard1: não envia quem lê um valor que ainda não foi calculado
        can_send0 = (count >= 5'd1) && dec_valid0 && path1_ready && !hazard0;

        can_send1 = (count >= 5'd2)&& dec_valid1 && path2_ready && !hazard1;

        //Envia a primeira
        if (can_send0) begin
            path1_valid = 1'b1;
            path1_instr = instr0;
            path1_ordem = ordem0;

            //IVAN FEATURE: PC a ser exposto
            path1_pc = pc0;

            path1_rs1_addr = dec_rs1_0;
            path1_rs2_addr = dec_rs2_0;

            //IVAN FEATURE: Campos da alocação acompanham a instrução
            path1_rob_id  = rob0;
            path1_previu  = previu0;
            path1_alvo    = alvo0;
            path1_sb_tail = sbt0;
            path1_lb_tail = lbt0;

            //IVAN FEATURE: Dado do Store vai ao Store Buffer pelo rob_id
            if (dec_dst0 == DST_STORE) begin
                store1_valid  = 1'b1;
                store1_rob_id = rob0;
                store1_dado   = path1_rs2_data;
            end

            n_out = 2'd1;

            //Envia a segunda seguindo a FIFO
            if (can_send1) begin
                path2_valid = 1'b1;
                path2_instr = instr1;
                path2_ordem = ordem1;

                //IVAN FEATURE: PC a ser exposto
                path2_pc = pc1;

                path2_rs1_addr = dec_rs1_1;
                path2_rs2_addr = dec_rs2_1;

                //IVAN FEATURE: Campos da alocação acompanham a instrução
                path2_rob_id  = rob1;
                path2_previu  = previu1;
                path2_alvo    = alvo1;
                path2_sb_tail = sbt1;
                path2_lb_tail = lbt1;

                //IVAN FEATURE: Dado do Store vai ao Store Buffer pelo rob_id
                if (dec_dst1 == DST_STORE) begin
                    store2_valid  = 1'b1;
                    store2_rob_id = rob1;
                    store2_dado   = path2_rs2_data;
                end

                n_out = 2'd2;
            end
        end

    end

    //Atualização da FIFO
    always @(posedge clk) begin

        if (rst) begin
            head <= 4'd0;
            tail <= 4'd0;
            count <= 5'd0;
            
            //Limpa as posições
            for (i = 0; i < 16; i = i + 1)
                buffer[i] <= 100'd0;

        end else begin
        
            // Retira as instrucoes despachadas
            head <= head + n_out;

            if (accept_in) begin
                write_count = 2'd0;

                //IVAN FEATURE: Ponto de corte começa no tail atual dos buffers
                sb_corte = sb_tail;
                lb_corte = lb_tail;

                for (i = 0; i < 3; i = i + 1) begin

                    //Instruçoes válidas
                    if (mei_valid[i]) begin

                        //IVAN FEATURE: Adicionando PC, rob_id, previsão e pontos de corte no
                        //armazenamento (rob_id = Rob_tail + write_count, igual à alocação)
                        case (i)  //Mantem a ordem
                            0: begin
                                buffer[tail + write_count] <= {lb_corte, sb_corte, mei_alvo0, mei_previu0,
                                    Rob_tail + {3'b0, write_count}, mei_pc0, mei_ordem0, mei_instr0};
                                gravado_dst = ent_dst0;
                            end
                            1: begin
                                buffer[tail + write_count]<= {lb_corte, sb_corte, mei_alvo1, mei_previu1,
                                    Rob_tail + {3'b0, write_count}, mei_pc1, mei_ordem1, mei_instr1};
                                gravado_dst = ent_dst1;
                            end
                            2: begin
                                buffer[tail + write_count]<= {lb_corte, sb_corte, mei_alvo2, mei_previu2,
                                    Rob_tail + {3'b0, write_count}, mei_pc2, mei_ordem2, mei_instr2};
                                gravado_dst = ent_dst2;
                            end
                        endcase
                        write_count = write_count + 2'd1;

                        //IVAN FEATURE: Loads/Stores desta entrada ficam antes do corte das seguintes
                        if (gravado_dst == DST_STORE) sb_corte = sb_corte + 5'd1;
                        if (gravado_dst == DST_LOAD)  lb_corte = lb_corte + 5'd1;
                    end
                end

                tail <= tail + n_in;
            end

            // Atualiza a ocupacao considerando entradas e saidas
            if (accept_in)
                count <= count + n_in - n_out;
            else
                count <= count - n_out;
        end
    end

endmodule
