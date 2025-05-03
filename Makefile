all:
	which pic
	which tbl
	which eqn
	which groff
	cat  vmthread.ms | pic | tbl | eqn | groff -Tpdf -ms > out.pdf

