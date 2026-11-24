#!/bin/sh
# Bateria de programas aleatórios comparados com o simulador de referência.
# Uso (de dentro de tb/aleatorio):  sh rodar.sh [quantidade]
N=${1:-50}
# No Windows (Git Bash) o Python costuma se chamar "python"; no Linux, "python3"
PY=$(command -v python3 || command -v python || command -v py)
[ -z "$PY" ] && { echo "Python 3 nao encontrado"; exit 1; }
iverilog -g2012 -o /tmp/tb_aleatorio tb_aleatorio.v ../../src/*.v || exit 1
for tipo in sem_desvio com_desvio; do
  ok=0; total=0
  for s in $(seq 1 $N); do
    if [ $tipo = sem_desvio ]; then "$PY" gerar_sem_desvio.py $s 150 > /dev/null || continue
    else "$PY" gerar_com_desvio.py $s 200 > /dev/null || continue; fi
    total=$((total+1))
    obtido=$(vvp -n /tmp/tb_aleatorio 2>/dev/null | grep -E "^[0-9]+ " | sed 's/ *$//')
    esperado=$(cat esperado)
    # sem desvio: o esperado tem x1..x7; compara só esses
    if [ $tipo = sem_desvio ]; then obtido=$(echo "$obtido" | cut -d' ' -f1-7); fi
    if [ "$obtido" = "$esperado" ]; then ok=$((ok+1)); else echo "FALHOU $tipo semente $s"; fi
  done
  echo "$tipo: $ok de $total corretos"
done
