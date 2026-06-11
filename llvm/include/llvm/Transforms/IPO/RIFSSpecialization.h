//===- RIFSSpecialization.h - PGO arg-value specialization -----*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Profile-guided specialization on dynamically-invariant integer arguments
// (RIFS prototype). Consumes the function-level !rifs.args metadata emitted
// by pgo-instr-use under -vp-arg-values. Gated by -rifs-mode: 0 = no-op,
// 1 = analyze only (dump scored candidates to stderr), 2 = transform (not
// implemented yet).
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_TRANSFORMS_IPO_RIFSSPECIALIZATION_H
#define LLVM_TRANSFORMS_IPO_RIFSSPECIALIZATION_H

#include "llvm/IR/PassManager.h"
#include "llvm/Support/Compiler.h"

namespace llvm {

class RIFSSpecializationPass : public PassInfoMixin<RIFSSpecializationPass> {
public:
  LLVM_ABI PreservedAnalyses run(Module &M, ModuleAnalysisManager &AM);
};

} // namespace llvm

#endif // LLVM_TRANSFORMS_IPO_RIFSSPECIALIZATION_H
