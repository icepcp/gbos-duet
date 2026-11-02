#!/bin/bash
# unguarded.sh <elf>: count LSE/RCpc instrs NOT preceded (within 2 insns) by the outline-atomics cbz w16 guard
aarch64-linux-gnu-objdump -d --no-show-raw-insn "$1" 2>/dev/null | awk -F'\t' -v f="$1" '
NF>=2{ split($2,a," "); m=a[1];
 if (m ~ /^(cas[al]*[bh]?|ld(add|clr|eor|set|smax|smin|umax|umin)[al]*[bh]?|st(add|clr|eor|set|smax|smin|umax|umin)l?[bh]?|swp[al]*[bh]?|ldapr[bh]?|ldapur[a-z]*)$/) {
   if (!(p1 ~ /^cbz w16/ || p2 ~ /^cbz w16/)) {n++; k[m]++} }
 p2=p1; p1=$2" "$3 }
END{ if(n){ s=""; for(x in k) s=s x":"k[x]" "; print f"\t"n"\t"s } }'
