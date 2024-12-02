# Changes made in this directory are invisible to the
# external web server.  To publish changed documents
# to the external web server, mk install or name.install
# To publish changed ps/pdf files, see the install rule.

< /sys/doc/fonts
NPROC = 1

ALL=\
		vmthread\

ALLPS=${ALL:%=%.ps}
HTML=${ALL:%=%.html} 
PDF=${ALL:%=%.pdf} 
FILES=vmthread
DIRS=vmthread
NAMES=$FILES $DIRS

all:V: ${FILES:%=%.ps} dirs

dirs:V:
	for(i in $DIRS) @{
		cd $i
		mk
	}

print:V: $ALLPS
	lp -H -i0 $prereq

# troff gets some scary-looking errors but they're okay
&.ps:D:	&.ms
	mac=(-ms)
	if(~ $stem comp utf 9 contents) mac=(-ms -mnihongo)
	{ echo $FONTS; cat $stem.ms } | pic | tbl | eqn | 
		troff $mac | lp -dstdout > $target
	/sys/doc/cleanps $target

%.trout:D:	%.ms
	mac=(-ms)
	if(~ $stem comp utf 9 contents) mac=($mac -mnihongo)
	{ echo $FONTS; cat $stem.ms } | pic | tbl | eqn | 
		troff $mac > $target

html:V: $HTML

9.trout 9.ps 9.html: network.pic

%.html: /$objtype/bin/htmlroff /sys/lib/tmac/tmac.s

index.html: contents.html
	cp contents.html index.html

&.html:D:	&.ms
	pic $stem.ms | tbl | eqn | htmlroff -ms -mhtml >$target

&.pdf:D:	&.ps
	cat /sys/doc/docfonts $stem.ps >_$stem.ps
	# distill _$stem.ps && mv _$stem.pdf $stem.pdf
	ps2pdf _$stem.ps $stem.pdf && rm -f _$stem.ps

pdf:V: $PDF

^(8½|acme|fs|il|net|sam|venti)/([^/]*\.(pdf|ps|html))'$':R:
	cd $stem1
	mk $stem2

^(8½|acme|fs|il|net|sam|venti)\.html'$':R: \1/\1.html
	cp $stem1/$stem1.html .

%.all:V:
	mk $stem.ps $stem.pdf $stem.html

%.install:V: %.html
	9fs other
	files=`{ls $stem.html $stem^*.png $stem/*.png $stem/*.html >[2]/dev/null}
	whatis stem
	whatis files
	cp $files /n/other/crp/sources.copy/sys/doc

%.page:V:	%.ps
	page -w $stem.ps

install:V: ${NAMES:%=%.install} release4.install release3.install

# ignore these
IGNHTML=title trademarks colophon troff
IGN=${IGNHTML:%=%.html} ${IGNHTML:%=%.install}

$IGN:QV:
	# nothing

