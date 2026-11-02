#!/bin/bash
# isa_scan.sh <file>: print counts of ARMv8.1+ instructions in an ELF's text
f="$1"
aarch64-linux-gnu-objdump -d --no-show-raw-insn "$f" 2>/dev/null | awk -F'\t' 'NF>=2{print $2}' | awk '{print $1}' | \
grep -E '^(cas|casa|casl|casal|casp|caspa|caspl|caspal|casb|cash|casab|casah|caslb|caslh|casalb|casalh|ld(add|clr|eor|set|smax|smin|umax|umin)(a|l|al)?(b|h)?|st(add|clr|eor|set|smax|smin|umax|umin)(l)?(b|h)?|swp(a|l|al)?(b|h)?|ldapr|ldaprb|ldaprh|ldapur.*|sqrdmlah|sqrdmlsh|sdot|udot|fcmla|fcadd|fjcvtzs|paciasp|autiasp|pacibsp|autibsp|bti|xpaclri|ldraa|ldrab|retaa|retab)$' | sort | uniq -c | sort -rn | awk -v f="$f" '{printf "%s\t%s\t%s\n", f, $2, $1}'
