module load_buffer(
    input wire clk, rst,

    // Despacho — até 3 instruções por ciclo
    input wire [2:0] v,                         // Quais slots são válidos
    input wire [2:0] dst1, dst2, dst3,           // Destino de cada instrução
    input wire [4:0] rob_id1, rob_id2, rob_id3, // Rob ids

    // Consulta ao ROB
    output wire [4:0]  lrid,    // Rob id do Load mais antigo sem leitura
    input  wire        lready,  // O endereço desse Load já foi calculado?

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
    reg [4:0] head, mem_ptr, tail;

    reg [4:0] lb_rid_reg;
    reg       mem_req_prev;

    wire [4:0] head2 = head + 1;
    wire [4:0] head3 = head + 2;
    wire [4:0] tail2 = tail + 1;
    wire [4:0] tail3 = tail + 2;

    // Filtragem interna — quais slots são Load
    wire is_load1 = v[0] & (dst1 == 3'b010);
    wire is_load2 = v[1] & (dst2 == 3'b010);
    wire is_load3 = v[2] & (dst3 == 3'b010);

    wire [2:0] dispatched = is_load1 + is_load2 + is_load3;

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
    assign mem_req = lready & (mem_ptr != tail) & !mem_done;
    assign lb_done = mem_done;
    assign lb_rid  = lb_rid_reg;

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
            lb_rid_reg   <= 5'd0;
            mem_req_prev <= 1'b0;
            for (i = 0; i < 16; i = i + 1)
                buffer[i] <= 38'b0;
        end else begin
            tail <= tail + dispatched;
            head <= head + aposentados;

            mem_req_prev <= mem_req;
            if(mem_req && !mem_req_prev)
                lb_rid_reg <= buffer[mem_ptr[3:0]][36:32];

            // Despacho compactado
            case({is_load1, is_load2, is_load3})
                3'b001: buffer[tail[3:0]]  <= {1'b0, rob_id3, 32'b0};
                3'b010: buffer[tail[3:0]]  <= {1'b0, rob_id2, 32'b0};
                3'b011: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id2, 32'b0};
                    buffer[tail2[3:0]] <= {1'b0, rob_id3, 32'b0};
                end
                3'b100: buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0};
                3'b101: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0};
                    buffer[tail2[3:0]] <= {1'b0, rob_id3, 32'b0};
                end
                3'b110: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0};
                    buffer[tail2[3:0]] <= {1'b0, rob_id2, 32'b0};
                end
                3'b111: begin
                    buffer[tail[3:0]]  <= {1'b0, rob_id1, 32'b0};
                    buffer[tail2[3:0]] <= {1'b0, rob_id2, 32'b0};
                    buffer[tail3[3:0]] <= {1'b0, rob_id3, 32'b0};
                end
            endcase

            if(mem_done) begin
                buffer[mem_ptr[3:0]][31:0] <= mem_data;
                buffer[mem_ptr[3:0]][37]   <= 1'b1;
                mem_ptr <= mem_ptr + 1;
            end
        end
    end
endmodule
