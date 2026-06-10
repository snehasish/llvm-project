; Test instrumentation of integer argument values (IPVK_ArgValue) under
; -vp-arg-values (RIFS prototype). Off by default.
; RUN: opt < %s -passes=pgo-instr-gen -vp-arg-values -rifs-min-func-size=2 -S | FileCheck %s --check-prefix=GEN
; RUN: opt < %s -passes=pgo-instr-gen -S | FileCheck %s --check-prefix=OFF
; RUN: opt < %s -passes=pgo-instr-gen,instrprof -vp-arg-values -rifs-min-func-size=2 -S | FileCheck %s --check-prefix=LOWER

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

;; One value-profile site per qualifying integer argument, in argument-index
;; order: site 0 = %m (i32, zext'd to i64), site 1 = %n (i64, used directly).
;; Skipped: %p (pointer), %d (float), %w (wider than 64 bits), %unused (no
;; users).
; GEN-LABEL: define i32 @foo(
; GEN: [[V0:%[0-9]+]] = zext i32 %m to i64
; GEN-NEXT: call void @llvm.instrprof.value_profile(ptr @__profn_foo, i64 {{-?[0-9]+}}, i64 [[V0]], i32 3, i32 0)
; GEN-NEXT: call void @llvm.instrprof.value_profile(ptr @__profn_foo, i64 {{-?[0-9]+}}, i64 %n, i32 3, i32 1)
; GEN-NOT: call void @llvm.instrprof.value_profile({{.*}} i32 3, i32 2)
define i32 @foo(i32 %m, i64 %n, ptr %p, double %d, i128 %w, i32 %unused) {
entry:
  %a = add i32 %m, 1
  %t = trunc i64 %n to i32
  %b = add i32 %a, %t
  %l = load i32, ptr %p
  %c = add i32 %b, %l
  ret i32 %c
}

;; Functions below -rifs-min-func-size get no argument value profiling.
; GEN-LABEL: define i32 @tiny(
; GEN-NOT: call void @llvm.instrprof.value_profile
define i32 @tiny(i32 %x) {
entry:
  ret i32 %x
}

; OFF-NOT: call void @llvm.instrprof.value_profile

;; Lowering: the generic value-profiling runtime call, sites 0 and 1.
; LOWER-LABEL: define i32 @foo(
; LOWER: call void @__llvm_profile_instrument_target(i64 %{{[0-9]+}}, ptr @__profd_foo, i32 0)
; LOWER: call void @__llvm_profile_instrument_target(i64 %n, ptr @__profd_foo, i32 1)
