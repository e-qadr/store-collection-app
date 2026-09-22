class AccountantCollectionReviewComparison {
  const AccountantCollectionReviewComparison({
    required this.branchReportedAmount,
    required this.reviewedAmount,
  });

  final double? branchReportedAmount;
  final double? reviewedAmount;

  bool get hasBranchReportedAmount => branchReportedAmount != null;
  bool get hasReviewedAmount => reviewedAmount != null && reviewedAmount! > 0;
  bool get canCompare => hasBranchReportedAmount && hasReviewedAmount;

  double get signedDifference =>
      (reviewedAmount ?? 0) - (branchReportedAmount ?? 0);
  double get differenceAmount => signedDifference.abs();
  bool get isMatch => canCompare && differenceAmount < 0.000001;
  bool get hasDifference => canCompare && !isMatch;
  bool get isIncrease => hasDifference && signedDifference > 0;

  String get differenceTypeLabel => isIncrease ? 'زيادة' : 'نقص';
}
