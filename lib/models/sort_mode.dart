enum SortMode { nameAsc, nameDesc, dateNewest, dateOldest, sizeLargest, sizeSmallest }

extension SortModeX on SortMode {
  String get label {
    switch (this) {
      case SortMode.nameAsc:
        return 'Name (A-Z)';
      case SortMode.nameDesc:
        return 'Name (Z-A)';
      case SortMode.dateNewest:
        return 'Date (Newest)';
      case SortMode.dateOldest:
        return 'Date (Oldest)';
      case SortMode.sizeLargest:
        return 'Size (Largest)';
      case SortMode.sizeSmallest:
        return 'Size (Smallest)';
    }
  }
}
