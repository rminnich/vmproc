all:
	cat  vmthread.ms | pic | tbl | eqn | groff -Tpdf -ms > out.pdf

