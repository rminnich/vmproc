.FP LucidaSans
.de EX
.nr x \\$1v
..
.de F1
.nr OI \\n(.iu
.nr PW 1v
.KF
.sp
..
.de T1
.F1
..
.de F2
.ds Fp Figure\ \\n(Fi
.ds Fn Figure\ \\n+(Fi
.ds Fq \\*(Fp
.F0
..
.de T2
.ds Tp Table\ \\n(Ti
.ds Tn Table\ \\n+(Ti
.ds Tq \\*(Tp
.T0
..
.de F0
.nr BD 1
.if t .ps \\n(PS-1
.if t .vs \\n(VSu-1p
.ft 1
.di DD
.ll \\n(.lu*3u/4u
.in 0
.fi
.ad b
.sp 0.5v
\f3\\*(Fq\f1\ \ \c
..
.de T0
.nr BD 1
.if t .ps \\n(PS-1
.if t .vs \\n(VSu-1p
.ft 1
.di DD
.ll \\n(.lu*3u/4u
.in 0
.fi
.ad b
.sp 0.5v
\f3\\*(Tq\f1\ \ \c
..
.de F3
.sp
.di
.br
.ll \\n(.lu*4u/3u
.if \\n(dl>\\n(BD .nr BD \\n(dl
.if \\n(BD<\\n(.l .in (\\n(.lu-\\n(BDu)/2u
.nf
.DD
.in \\n(OIu
.nr BD 0
.fi
.KE
.vs \\n(VSu
..
.de T3
.F3
..
.de LT
.if !\\n(PO .ie n .nr PO 1.5i
.el .nr PO 1.3i
.po \\n(POu
.LP
.rs
.if !"\\$1"" \{\
.	vs -2p
.if !"\\$1"AT&T" .ta 3.9i 4.55i
.if "\\$1"AT&T" .ta 4.9i 5.45i
.	sp .2i
.	nf
.	if !"\\$1"AT&T" \d\s12\f(HB\\$1\s0\fP\u	\s36\(FA\s0
.	if "\\$1"AT&T" 	\s36\(LH\s0
.	br
\s7\l'7i'\s0
.	br
.	if !"\\$2"" .ds xR "		\\$2
.	ds xP 908-582-3000
.	if !"\\$3"" .ds xP \\$3
.	if !"\\$1"AT&T" \s9\f(HBBell Laboratories\fP		\fH600 Mountain Avenue
.	if "\\$1"AT&T" \s8\f(HBAT&T Bell Laboratories\fP		\fH700 Mountain Avenue
.	if !"\\$2"" \\*(xR
		Murray Hill, NJ 07974-0636
		\\*(xP
.	if !"\\$4"" 		\\$4
.	if !"\\$5"" 		\\$5
.	if !"\\$6"" 		\\$6
.	if !"\\$7"" 		\\$7
.ft 1
.ps
.	sp -.75i
.	vs
.	fi \}
.if n \{\
.	sp 1i
.	in 4.55i\}
.if t \{\
.	sp 1.45i
.	in 3.5i\}
.ll 8i
\\*(DY
.ll
.in 0
.br
.if t .sp 3
.if n \{\
.	sp
.	na\}
.nf
.rm CF
.de SG	\" nested defn
.sp 2
.ta 3.5i
	\\\\*(Sg
.sp 3
	\\\\$1
.ds CH
\\..
..
.de EX
.P1
\s-4
..
.de EE
\s+4
.P2
..
.nr PS 12	\" 12-point type
.nr VS 14p	\" 14-point base-line spacing
.nr PD 0u		\" extra space between paragraphs
.nr PI 1.5m	\" paragraph indent
.nr Fi 1 +1
.nr Ti 1 +1
.ds Fn Figure\ \\n(Fi
.ds Tn Table\ \\n(Ti
.ds Sg Sincerely,
.nr XP 2	\" delta point size for program
.nr XV 2p	\" delta vertical for programs
.nr XT 4	\" delta tab stop for programs
.nr DV .5v	\" space before start of program
