; Test RIFS analyze mode (-rifs-mode=1): candidate enumeration from
; !rifs.args metadata and InstCostVisitor scoring, dump only — no transform.
; REQUIRES: x86-registered-target
; RUN: opt < %s -passes=rifs-specialization -rifs-mode=1 -S -o %t.ll 2>&1 | FileCheck %s --check-prefix=ANALYZE
; RUN: FileCheck %s --check-prefix=UNCHANGED < %t.ll
; RUN: opt < %s -passes=rifs-specialization -S 2>&1 | FileCheck %s --check-prefix=OFF

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

;; @branchy specialized on %m = 7: the icmp folds to true, the conditional
;; branch becomes unconditional, and block %slow goes dead. Hand-computed
;; x86 TCK_CodeSize savings: icmp(1) + br(1) + dead block [sdiv(4) + mul(1)
;; + ret(1)] = 8. TCK_Latency counts only the folded instructions, each
;; weighted by BlockFreq/EntryFreq = 1: icmp(1) + br(1) = 2 (dead-block
;; instructions are a code-size-only saving in this cost model).
; ANALYZE: RIFS: fn=branchy arg=0 value=7 count=970 total=1000 ratio=0.9700 entry=1000 size=7 codesize=8 latency=2
define i32 @branchy(i32 %m, i32 %x) !prof !10 !rifs.args !20 {
entry:
  %c = icmp eq i32 %m, 7
  br i1 %c, label %fast, label %slow, !prof !30
fast:
  %f = add i32 %x, 1
  ret i32 %f
slow:
  %d = sdiv i32 %x, %m
  %e = mul i32 %d, 3
  ret i32 %e
}

;; @passthru's body has no foldable dependence on %m: invariance is high
;; (98%) but the savings must be zero — the K3 guard-overhead control of
;; design.md §3-E1 in miniature.
; ANALYZE: RIFS: fn=passthru arg=0 value=3 count=490 total=500 ratio=0.9800 entry=500 size=2 codesize=0 latency=0
;; Module denominator: profile-weighted dynamic instructions across all
;; profiled functions. @branchy: entry [icmp,br] 2x1000 + fast [add,ret]
;; 2x970 + slow [sdiv,mul,ret] 3x30 = 4030; @passthru: [add,ret] 2x500 =
;; 1000; total 5030.
; ANALYZE: RIFS-MODULE: id={{.*}} dyninsts=5030
define i32 @passthru(i32 %m, i32 %x) !prof !11 !rifs.args !21 {
entry:
  %s = add i32 %x, 5
  ret i32 %s
}

;; Analyze mode must not change the IR: same two functions, no clones.
; UNCHANGED: define i32 @branchy(
; UNCHANGED: define i32 @passthru(
; UNCHANGED-NOT: define

;; Default mode is 0: completely silent.
; OFF-NOT: RIFS:

!10 = !{!"function_entry_count", i64 1000}
!11 = !{!"function_entry_count", i64 500}
!20 = !{!22}
!21 = !{!23}
!22 = !{i32 0, i64 1000, i64 7, i64 970}
!23 = !{i32 0, i64 500, i64 3, i64 490}
!30 = !{!"branch_weights", i32 970, i32 30}
