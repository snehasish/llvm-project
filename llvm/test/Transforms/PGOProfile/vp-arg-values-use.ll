; Test use-side emission of function-level !rifs.args metadata from
; IPVK_ArgValue profiles under -vp-arg-values (RIFS prototype).
; RUN: llvm-profdata merge %S/Inputs/vp-arg-values.proftext -o %t.profdata
; RUN: opt < %s -passes=pgo-instr-use -pgo-test-profile-file=%t.profdata -vp-arg-values -rifs-min-func-size=2 -S | FileCheck %s
; RUN: opt < %s -passes=pgo-instr-use -pgo-test-profile-file=%t.profdata -S 2>&1 | FileCheck %s --check-prefix=NOFLAG

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

;; One tuple per profiled argument site, in argument-index order:
;; !{i32 argno, i64 total, i64 value, i64 count, ...}, top 3 values by
;; count. The total is the function entry count (1000), not the sum of the
;; site's value counts.
; CHECK: define i32 @foo({{.*}}){{.*}} !rifs.args ![[RA:[0-9]+]]
; CHECK-DAG: ![[RA]] = !{![[A0:[0-9]+]], ![[A1:[0-9]+]]}
; CHECK-DAG: ![[A0]] = !{i32 0, i64 1000, i64 7, i64 970, i64 3, i64 12, i64 9, i64 8}
; CHECK-DAG: ![[A1]] = !{i32 1, i64 1000, i64 42, i64 1000}

;; Without -vp-arg-values the profile's arg-value records are ignored:
;; no metadata and no stale-profile warning.
; NOFLAG-NOT: rifs.args
; NOFLAG-NOT: Inconsistent number of value sites
define i32 @foo(i32 %m, i64 %n, ptr %p, i32 %unused) {
entry:
  %a = add i32 %m, 1
  %t = trunc i64 %n to i32
  %b = add i32 %a, %t
  %l = load i32, ptr %p
  %c = add i32 %b, %l
  ret i32 %c
}
