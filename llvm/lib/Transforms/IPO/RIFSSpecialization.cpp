//===- RIFSSpecialization.cpp - PGO arg-value specialization -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// RIFS prototype: specialize functions on integer arguments whose profiled
// runtime value is dynamically invariant (one value covers most entries),
// behind a compare-and-branch guard at the call sites. This file currently
// implements candidate enumeration and scoring (analyze mode); the transform
// comes later.
//
// Candidates come from !rifs.args function metadata (see
// PGOUseFunc::annotateArgValueMetadata): per profiled argument site,
// !{i32 argno, i64 total, i64 value0, i64 count0, ...} with values sorted by
// count and total equal to the function entry count.
//
// Scoring reuses FunctionSpecialization's InstCostVisitor, which needs a
// solved SCCPSolver. Unlike FuncSpec (which runs inside IPSCCP and shares its
// module-wide solver), this pass runs after PGO annotation and solves
// per-function: entry block executable, all arguments overdefined — the same
// conservative assumptions FuncSpec scores under.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/IPO/RIFSSpecialization.h"
#include "llvm/Analysis/BlockFrequencyInfo.h"
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/Analysis/TargetTransformInfo.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/IPO/FunctionSpecialization.h"
#include "llvm/Transforms/Utils/SCCPSolver.h"

using namespace llvm;

namespace llvm {
// 0 = off, 1 = analyze (dump scored candidates to stderr, no transform),
// 2 = transform (not implemented yet). Referenced by PassBuilderPipelines to
// decide whether to add this pass at the post-PGO-annotation (ICP) slot.
cl::opt<unsigned> RIFSMode(
    "rifs-mode", cl::init(0),
    cl::desc("RIFS prototype mode: 0 = off, 1 = analyze (dump scored "
             "candidates to stderr), 2 = transform (not implemented)"));
} // namespace llvm

static uint64_t extractMDInt(const MDNode *N, unsigned I) {
  return mdconst::extract<ConstantInt>(N->getOperand(I))->getZExtValue();
}

PreservedAnalyses RIFSSpecializationPass::run(Module &M,
                                              ModuleAnalysisManager &AM) {
  if (RIFSMode == 0)
    return PreservedAnalyses::all();

  FunctionAnalysisManager &FAM =
      AM.getResult<FunctionAnalysisManagerModuleProxy>(M).getManager();
  const DataLayout &DL = M.getDataLayout();
  auto GetTLI = [&FAM](Function &F) -> const TargetLibraryInfo & {
    return FAM.getResult<TargetLibraryAnalysis>(F);
  };
  auto GetBFI = [&FAM](Function &F) -> BlockFrequencyInfo & {
    return FAM.getResult<BlockFrequencyAnalysis>(F);
  };

  for (Function &F : M) {
    if (F.isDeclaration())
      continue;
    MDNode *ArgsMD = F.getMetadata("rifs.args");
    if (!ArgsMD)
      continue;

    SCCPSolver Solver(DL, GetTLI, F.getContext());
    Solver.markBlockExecutable(&F.getEntryBlock());
    for (Argument &AI : F.args())
      Solver.markOverdefined(&AI);
    bool ResolvedUndefs = true;
    while (ResolvedUndefs) {
      Solver.solve();
      ResolvedUndefs = Solver.resolvedUndefsIn(F);
    }

    TargetTransformInfo &TTI = FAM.getResult<TargetIRAnalysis>(F);
    uint64_t EntryCount =
        F.getEntryCount() ? F.getEntryCount()->getCount() : 0;
    unsigned FuncSize = F.getInstructionCount();

    for (const MDOperand &Op : ArgsMD->operands()) {
      const auto *ArgMD = cast<MDNode>(Op.get());
      // !{i32 argno, i64 total, i64 value0, i64 count0, ...}; sites with no
      // recorded values were skipped at annotation time, but guard anyway.
      if (ArgMD->getNumOperands() < 4)
        continue;
      uint64_t ArgNo = extractMDInt(ArgMD, 0);
      uint64_t Total = extractMDInt(ArgMD, 1);
      uint64_t Value = extractMDInt(ArgMD, 2);
      uint64_t Count = extractMDInt(ArgMD, 3);
      // Stale metadata (e.g. signature changed since annotation): skip.
      if (ArgNo >= F.arg_size())
        continue;
      Argument *A = F.getArg(ArgNo);
      auto *IntTy = dyn_cast<IntegerType>(A->getType());
      if (!IntTy || IntTy->getBitWidth() > 64)
        continue;
      // The profiled value was zero-extended to i64; truncate back.
      Constant *C = ConstantInt::get(IntTy, Value, /*IsSigned=*/false);

      // One specialization per argument on its top value: score the savings
      // of substituting C for A. A fresh visitor per candidate, since
      // KnownConstants accumulates per specialization.
      InstCostVisitor Visitor(GetBFI, &F, DL, TTI, Solver);
      Cost CodeSize = Visitor.getCodeSizeSavingsForArg(A, C);
      CodeSize += Visitor.getCodeSizeSavingsFromPendingPHIs();
      Cost Latency = Visitor.getLatencySavingsForKnownConstants();
      double Ratio = Total ? (double)Count / (double)Total : 0.0;

      errs() << "RIFS: fn=" << F.getName() << " arg=" << ArgNo
             << " value=" << Value << " count=" << Count
             << " total=" << Total << format(" ratio=%.4f", Ratio)
             << " entry=" << EntryCount << " size=" << FuncSize
             << " codesize=" << CodeSize << " latency=" << Latency << "\n";
    }
  }

  // Module-level denominator for the E0 claimed-savings-share metric:
  // profile-weighted dynamic instruction count over all profiled functions,
  // candidates or not. Emitted once per module so per-TU dumps can be
  // aggregated without a second pass over the corpus.
  uint64_t DynInsts = 0;
  for (Function &F : M) {
    if (F.isDeclaration())
      continue;
    auto EC = F.getEntryCount();
    if (!EC || EC->getCount() == 0)
      continue;
    auto &BFI = FAM.getResult<BlockFrequencyAnalysis>(F);
    for (BasicBlock &BB : F) {
      std::optional<uint64_t> BBCount = BFI.getBlockProfileCount(&BB);
      if (!BBCount)
        continue;
      uint64_t Size = 0;
      for (Instruction &I : BB)
        if (!I.isDebugOrPseudoInst())
          ++Size;
      DynInsts += *BBCount * Size;
    }
  }
  errs() << "RIFS-MODULE: id=" << M.getName() << " dyninsts=" << DynInsts
         << "\n";

  // Analyze mode reads the IR and writes only to stderr.
  return PreservedAnalyses::all();
}
