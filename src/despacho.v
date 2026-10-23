module despacho(
    input wire clk, rst,

    //Instruções enviadas pelo MEI
    input  wire [2:0]  mei_valid, //Se a isntrução enviada é valida

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
    input  wire [31:0] path2_rs2_data

);
    //Renomeação do sinal enviado pelo ROB
    wire rob_stop = stop;

    //Determinam o destino da instruçao
    localparam [2:0] DST_REG   = 3'b000;
    localparam [2:0] DST_LOAD  = 3'b010;
    localparam [2:0] DST_STORE = 3'b100;

    //Armazenamento do despacho
    reg [63:0] buffer [0:15];
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

    assign instr1 = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][31:0] : 32'd0;
    assign ordem1 = (count >= 5'd2) ? buffer[(head + 4'd1) & 4'hF][63:32] : 32'd0;

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

        accept_in = !mei_stop && (n_in <= free_slots);
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

        n_out = 2'd0;
        can_send0 = 1'b0;
        can_send1 = 1'b0;

        //Confere se as instruçoes respeitam os bloqueios
        can_send0 = (count >= 5'd1) && dec_valid0 && path1_ready && !rob_stop && !(dec_dst0 == DST_LOAD  
                 && load_buffer_stop) && !(dec_dst0 == DST_STORE && store_buffer_stop);

        can_send1 = (count >= 5'd2)&& dec_valid1 && path2_ready && !rob_stop && !(dec_dst1 == DST_LOAD  
                 && load_buffer_stop) && !(dec_dst1 == DST_STORE && store_buffer_stop);

        //Envia a primeira
        if (can_send0) begin
            path1_valid = 1'b1;
            path1_instr = instr0;
            path1_ordem = ordem0;

            path1_rs1_addr = dec_rs1_0;
            path1_rs2_addr = dec_rs2_0;

            v[0] = 1'b1;
            dst1 = dec_dst0;
            rd1 = dec_rd0;
            rob_id1 = Rob_tail;

            if (dec_dst0 == DST_STORE)
                dado1 = path1_rs2_data;

            n_out = 2'd1;

            //Envia a segunda seguindo a FIFO
            if (can_send1) begin
                path2_valid = 1'b1;
                path2_instr = instr1;
                path2_ordem = ordem1;

                path2_rs1_addr = dec_rs1_1;
                path2_rs2_addr = dec_rs2_1;

                v[1] = 1'b1;
                dst2 = dec_dst1;
                rd2 = dec_rd1;
                rob_id2 = Rob_tail + 5'd1;

                if (dec_dst1 == DST_STORE)
                    dado2 = path2_rs2_data;

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
                buffer[i] <= 64'd0;

        end else begin
        
            // Retira as instrucoes despachadas
            head <= head + n_out;

            if (accept_in) begin
                write_count = 2'd0;

                for (i = 0; i < 3; i = i + 1) begin

                    //Instruçoes válidas
                    if (mei_valid[i]) begin

                        case (i)  //Mantem a ordem
                            0: buffer[tail + write_count] <= {mei_ordem0, mei_instr0};
                            1: buffer[tail + write_count]<= {mei_ordem1, mei_instr1};
                            2: buffer[tail + write_count]<= {mei_ordem2, mei_instr2};
                        endcase
                        write_count = write_count + 2'd1;
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
