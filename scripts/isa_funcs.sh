#!/bin/bash
# isa_funcs.sh <elf>: list functions containing trapping v8.1+ instrs, excluding outline-atomic helpers
aarch64-linux-gnu-objdump -d --no-show-raw-insn "$1" 2>/dev/null | awk -v f="$1" '/^[0-9a-f]+ <.*>:$/{fn=$2} $0 ~ /\t(cas|casa|casl|casal|cas[ab]?[bh]?|ld(add|clr|eor|set|smax|smin|umax|umin)[al]*[bh]?|st(add|clr|eor|set)[l]?[bh]?|swp[al]*[bh]?|ldapr[bh]?|sdot|udot|retaa|retab)\t/{print f"\t"fn}' | grep -v '__aarch64_' | sort | uniq -c
