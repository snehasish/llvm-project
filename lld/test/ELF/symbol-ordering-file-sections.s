# REQUIRES: x86
## -z symbol-ordering-sections lets `@section` and `@default` directives in
## --symbol-ordering-file choose the text output section of listed functions.
## Only input sections holding exactly one function may move, so this also
## works with -ffunction-sections -fno-unique-section-names (every function in
## its own section named ".text").

# RUN: rm -rf %t && split-file %s %t && cd %t
# RUN: llvm-mc -filetype=obj -triple=x86_64 a.s -o a.o
# RUN: ld.lld -z keep-text-section-prefix -z symbol-ordering-sections \
# RUN:   --symbol-ordering-file=ord a.o -o out 2>&1 | FileCheck %s --check-prefix=WARN
# RUN: llvm-objdump -t out | FileCheck %s

## shared2 does not own its input section (_start starts it), so it is not moved.
# WARN: warning: symbol ordering file: shared2 shares its input section with other functions; @section ignored

## hot1 is demoted, cold1 and plain1 are promoted, plain2 (bare ".text" section)
## and plain3 (unique name) follow @default, the .text.split part and the
## multi-function bare .text section are untouched.
# CHECK-DAG: .text.unlikely {{.*}} hot1
# CHECK-DAG: .text.hot {{.*}} cold1
# CHECK-DAG: .text.hot {{.*}} plain1
# CHECK-DAG: .text.unlikely {{.*}} plain2
# CHECK-DAG: .text.unlikely {{.*}} plain3
# CHECK-DAG: .text.split {{.*}} hot1.cold
# CHECK-DAG: .text {{.*}} _start
# CHECK-DAG: .text {{.*}} shared2

## Without -z symbol-ordering-sections (or with -z nosymbol-ordering-sections)
## the directives are plain (unknown) symbol names and the section name prefixes
## decide.
# RUN: ld.lld -z keep-text-section-prefix --no-warn-symbol-ordering \
# RUN:   --symbol-ordering-file=ord a.o -o out2
# RUN: llvm-objdump -t out2 | FileCheck %s --check-prefix=NOFLAG
# RUN: ld.lld -z keep-text-section-prefix -z symbol-ordering-sections \
# RUN:   -z nosymbol-ordering-sections --no-warn-symbol-ordering \
# RUN:   --symbol-ordering-file=ord a.o -o out3
# RUN: llvm-objdump -t out3 | FileCheck %s --check-prefix=NOFLAG
# NOFLAG-DAG: .text.hot {{.*}} hot1
# NOFLAG-DAG: .text.unlikely {{.*}} cold1
# NOFLAG-DAG: .text {{.*}} plain1
# NOFLAG-DAG: .text {{.*}} plain2
# NOFLAG-DAG: .text {{.*}} plain3

## A directive naming anything else is an error.
# RUN: not ld.lld -z symbol-ordering-sections --symbol-ordering-file=bad \
# RUN:   a.o -o /dev/null 2>&1 | FileCheck %s --check-prefix=BAD
# BAD: @section expects .text, .text.hot, .text.unlikely or .text.unknown

#--- ord
@section .text.unlikely
hot1
@section .text.hot
cold1
plain1
shared2
@default .text.unlikely

#--- bad
@section .text.startup

#--- a.s
.section .text.hot.hot1,"ax",@progbits
.globl hot1
.type hot1,@function
hot1:
  ret

.section .text.unlikely.cold1,"ax",@progbits
.globl cold1
.type cold1,@function
cold1:
  ret

.section .text,"ax",@progbits,unique,1
.globl plain1
.type plain1,@function
plain1:
  ret

.section .text,"ax",@progbits,unique,2
.globl plain2
.type plain2,@function
plain2:
  ret

.section .text.plain3,"ax",@progbits
.globl plain3
.type plain3,@function
plain3:
  ret

.section .text.split.hot1,"ax",@progbits
.globl hot1.cold
.type hot1.cold,@function
hot1.cold:
  ret

.section .text,"ax",@progbits
.globl _start
.type _start,@function
_start:
  ret
.globl shared2
.type shared2,@function
shared2:
  ret
