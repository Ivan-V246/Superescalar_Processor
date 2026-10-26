module load_buffer(
    input wire clk, rst,

    // Despacho — até 3 instruções por ciclo
    input wire [2:0] v,                         // Quais slots são válidos
    input wire [2:0] dst1, dst2, dst3,           // Destino de cada instrução
    input wire [4:0] rob_id1, rob_id2, rob_id3, // Rob ids

    // Consulta ao ROB
    output wire [4:0]  lrid,    // Rob id do Load mais antigo sem leitura
    input  wire        lready,  // O endereço desse Load já foi calculado?

    // Consulta ao Store Buffer
    input  wire [4:0]  sb_tail,  // Tail do Store Buffer, para a idade do Load
    output wire [4:0]  q_idade,  // Idade do Load mais antigo sem leitura
    input  wire        q_espera, // Há Store mais antigo de endereço desconhecido que pode coincidir
    input  wire        q_hit,    // Há Store mais antigo no mesmo endereço: o dado vem dele
    input  wire [31:0] q_dado,   // Dado do Store (forwarding)

    // Memória
    output wire        mem_req,
    input  wire [31:0] mem_data,
    input  wire        mem_done,

    // Sinaliza pro ROB
    output wire        lb_done,
    output wire [4:0]  lb_rid,

    // Commits do ROB
    input wire [2:0]  cv,
    input wire [4:0] crob_id1, crob_id2, crob_id3,

    // Escrita no banco
    output wire [31:0] lb_dado1, lb_dado2, lb_dado3,

    // Sinal de parada
    output wire stop
);
    // Layout:
    // [37]    → dado_pronto
    // [36:32] → rob_id (5 bits)
    // [31:0]  → dado (32 bits)
    reg [37:0] buffer [0:15];
    reg [4:0]  idade  [0:15];   // Tail do Store Buffer no despacho: Stores mais antigos estão antes dele
    reg [4:0] head, mem_ptr, tail;

    wire [4:0] head2 = head + 1;
    wire [4:0] head3 = head + 2;
    wire [4:0] tail2 = tail + 1;
    wire [4:0] tail3 = tail + 2;

    // Filtragem interna — quais slots são Load
    wire is_load1 = v[0] & (dst1 == 3'b010);
    wire is_load2 = v[1] & (dst2 == 3'b010);
    wire is_load3 = v[2] & (dst3 == 3'b010);

    wire [2:0] dispatched = is_load1 + is_load2 + is_load3;

    // Idade — conta os Stores dos slots anteriores do mesmo grupo
    wire is_store1 = v[0] & (dst1 == 3'b100);
    wire is_store2 = v[1] & (dst2 == 3'b100);

    wire [4:0] idade1 = sb_tail;
    wire [4:0] idade2 = sb_tail + is_store1;
    wire [4:0] idade3 = sb_tail + is_store1 + is_store2;

    // Commit
    wire commit1 = (cv[0] & (crob_id1 == buffer[head[3:0]][36:32]))  |
                   (cv[1] & (crob_id2 == buffer[head[3:0]][36:32]))  |
                   (cv[2] & (crob_id3 == buffer[head[3:0]][36:32]));

    wire commit2 = commit1 &
                   ((cv[1] & (crob_id2 == buffer[head2[3:0]][36:32])) |
                    (cv[2] & (crob_id3 == buffer[head2[3:0]][36:32])));

    wire commit3 = commit2 &
                   (cv[2] & (crob_id3 == buffer[head3[3:0]][36:32]));

    wire [2:0] aposentados = commit1 + commit2 + commit3;

    assign lrid    = buffer[mem_ptr[3:0]][36:32];
    assign q_idade = idade[mem_ptr[3:0]];

    // O Load em mem_ptr termina pela memória (um ciclo depois do mem_req)
    // ou por forwarding (no mesmo ciclo da consulta)
    wire pronto = lready & !q_espera & (mem_ptr != tail) & !mem_done;
    wire fwd    = pronto & q_hit;
    assign mem_req = pronto & !q_hit;

    wire        termina   = mem_done | fwd;
    wire [31:0] dado_lido = fwd ? q_dado : mem_data;

    // mem_ptr só avança quando o Load termina, então ele ainda aponta para esse Load
    assign lb_done = termina;
    assign lb_rid  = buffer[mem_ptr[3:0]][36:32];

    assign lb_dado1 = buffer[head[3:0]][31:0];
    assign lb_dado2 = buffer[head2[3:0]][31:0];
    assign lb_dado3 = buffer[head3[3:0]][31:0];

    assign stop = ((tail - head) > 5'd13);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head         <= 5'd0;
            mem_ptr      <= 5'd0;
            tail         <= 5'd0;
            for (i = 0; i < 16; i = i + 1) begin
                buffer[i] <= 38'b0;
                idade[i]  <= 5'b0;
            end
        end else begin
            tail <= tail + dispatched;
            head <= head + aposentados;

            // Despacho compactado
            case({is_load1, is_load2, is_load3})
                3'b001: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id3, 32'b0}; idade[tail[3:0]]  <= idade3;
                end
                3'b010: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id2, 32'b0}; idade[tail[3:0]]  <= idade2;
                end
                3'b011: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id2, 32'b0}; idade[tail[3:0]]  <= idade2;
                    buffer[tail2[3:0]] <= {1'b0, rob_id3, 32'b0}; idade[tail2[3:0]] <= idade3;
                end
                3'b100: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                end
                3'b101: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                    buffer[tail2[3:0]] <= {1'b0, rob_id3, 32'b0}; idade[tail2[3:0]] <= idade3;
                end
                3'b110: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                    buffer[tail2[3:0]] <= {1'b0, rob_id2, 32'b0}; idade[tail2[3:0]] <= idade2;
                end
                3'b111: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0}; idade[tail[3:0]]  <= idade1;
                    buffer[tail2[3:0]] <= {1'b0, rob_id2, 32'b0}; idade[tail2[3:0]] <= idade2;
                    buffer[tail3[3:0]] <= {1'b0, rob_id3, 32'b0}; idade[tail3[3:0]] <= idade3;
                end
            endcase

            if(termina) begin
                buffer[mem_ptr[3:0]][31:0] <= dado_lido;
                buffer[mem_ptr[3:0]][37]   <= 1'b1;
                mem_ptr <= mem_ptr + 1;
            end
        end
    end
endmodule
