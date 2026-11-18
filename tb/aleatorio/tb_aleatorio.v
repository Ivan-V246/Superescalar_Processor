`timescale 1ns/1ps
// Executa o programa de prog_aleatorio e imprime x1..x9 e os contadores do despacho.
module tb_aleatorio;
  reg clk=0, rst=1; always #5 clk=~clk;
  processador dut(.clk(clk),.rst(rst));
  integer i;
  initial begin
    for (i=0;i<256;i=i+1) dut.mei.memoria[i]=32'h0;
    $readmemh("prog_aleatorio", dut.mei.memoria);
    for (i=0;i<2048;i=i+1) dut.med.memoria[i]=0;
    repeat(2) @(posedge clk); #1 rst=0;
    repeat(5000) @(posedge clk); #1;
    for (i=1;i<10;i=i+1) $write("%0d ", dut.banco.registradores[i]);
    $display("");
    $display("CNT ciclos=%0d enviadas=%0d fora=%0d desc=%0d vazia=%0d oper=%0d estr=%0d fim=%0d bloq=%0d e1=%0d e2=%0d e3=%0d",
      dut.desp.cnt_ciclos, dut.desp.cnt_enviadas, dut.desp.cnt_fora_de_ordem, dut.desp.cnt_parado_descarte,
      dut.desp.cnt_parado_vazia, dut.desp.cnt_parado_operandos, dut.desp.cnt_parado_estrutura, dut.desp.cnt_parado_fim,
      dut.desp.cnt_entrada_bloqueada, dut.desp.cnt_envio_1, dut.desp.cnt_envio_2, dut.desp.cnt_envio_3);
    $finish;
  end
endmodule
